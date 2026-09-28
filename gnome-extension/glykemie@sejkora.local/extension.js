// GNOME Shell rozšíření: glykemie na obrazovce + alarm.
// Data bere ze stejného Workeru jako displej na iPhonu (viz CLAUDE.md).
//
// Nastavení je v config.json vedle tohohle souboru a načítá se ZA BĚHU –
// po uložení se změna projeví hned, není potřeba se odhlašovat. Odhlášení
// je nutné jen při změně tohohle .js souboru (omezení Waylandu).

import GObject from 'gi://GObject';
import St from 'gi://St';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Soup from 'gi://Soup?version=3.0';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const PAGE_URL = 'https://glykemie.sejkoramartin.workers.dev';
const API_URL = `${PAGE_URL}/api/glucose`;

const COLOR_OK = '#33cc55';
const COLOR_ALERT = '#ff4444';
const COLOR_STALE = 'rgba(255,255,255,0.5)';

// Použije se, když config.json chybí nebo je rozbitý.
const DEFAULTS = {
    refreshSeconds: 60,
    lowMmol: 4.2,
    highMmol: 9.5,
    staleMinutes: 5,

    panelEnabled: false,

    hudEnabled: true,
    hudClickable: true,
    hudMonitor: -1,
    hudCorner: 'bottom-right',
    hudMarginX: 200,
    hudMarginY: 14,
    hudValueSize: 30,
    hudArrowSize: 26,
    hudShowAge: false,
    hudAgeSize: 20,
    hudBackground: false,
    hudOpacity: 1,

    alertEnabled: true,
    alertMonitor: -1,
    alertValueSize: 160,
    alertTitleSize: 48,
    alertSound: true,
    alertSoundName: 'alarm-clock-elapsed',
    alertSoundRepeatSeconds: 8,
    alertPulse: true,
    alertAutoHideMinutes: 0,

    notifyCooldownMinutes: 15,
    errorsBeforeNotify: 5,
};

function loadConfig(dir) {
    try {
        const [ok, contents] = dir.get_child('config.json').load_contents(null);
        if (!ok)
            return {...DEFAULTS};
        const parsed = JSON.parse(new TextDecoder('utf-8').decode(contents));
        const cfg = {...DEFAULTS, ...parsed};

        // Pojistka: kdyby si někdo vypnul obojí, neměl by jak se k nastavení
        // dostat – v takovém případě vrátíme panelový indikátor.
        if (!cfg.panelEnabled && !cfg.hudEnabled)
            cfg.panelEnabled = true;

        return cfg;
    } catch (e) {
        logError(e, 'Glykemie: config.json nejde načíst, beru výchozí hodnoty');
        return {...DEFAULTS};
    }
}

// Panelový indikátor je teď volitelný (výchozí je vypnutý) – hodnota se
// primárně ukazuje v HUD, který si nese vlastní nabídku.
const GlykemiePanelButton = GObject.registerClass(
class GlykemiePanelButton extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Glykemie', false);
        this.label = new St.Label({
            text: '…',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'glykemie-label',
        });
        this.add_child(this.label);
    }
});

class GlykemieMonitor {
    constructor(config, uuid) {
        this._cfg = config;
        this._uuid = uuid;

        this._session = new Soup.Session();
        // ať se to při zakolísání sítě nezasekne na desítky sekund
        this._session.timeout = 15;
        this._cancellable = new Gio.Cancellable();

        this._timeoutId = 0;
        this._retryId = 0;
        this._notifySource = null;
        this._notifyState = 'ok';
        this._lastNotifyTime = 0;
        this._errorCount = 0;
        this._errorNotified = false;
        this._lastData = null;

        this._alert = null;
        this._alertPulseId = 0;
        this._alertSoundId = 0;
        this._alertHideId = 0;

        this._statusItems = [];

        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed',
            () => {
                this._positionHud();
                this._positionAlert();
            }
        );

        this._buildUi();
        this._restartTimer();
        this._refresh();
    }

    // Zavolá se při každé změně config.json.
    applyConfig(config) {
        this._cfg = config;

        this._destroyUi();
        this._buildUi();
        this._restartTimer();

        if (this._lastData)
            this._onData(this._lastData);
        else
            this._refresh();
    }

    _restartTimer() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
        this._timeoutId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            Math.max(10, this._cfg.refreshSeconds),
            () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    // ---------- UI ----------

    _buildUi() {
        this._statusItems = [];

        if (this._cfg.panelEnabled) {
            this._panel = new GlykemiePanelButton();
            Main.panel.addToStatusArea(this._uuid, this._panel, 0, 'right');
            this._populateMenu(this._panel.menu);
        }

        if (this._cfg.hudEnabled)
            this._buildHud();
    }

    _destroyUi() {
        this._closeHudMenu();

        if (this._hudMenu) {
            this._hudMenuManager?.removeMenu(this._hudMenu);
            this._hudMenu.destroy();
            this._hudMenu = null;
            this._hudMenuManager = null;
        }
        this._destroyHud();

        if (this._panel) {
            this._panel.destroy();
            this._panel = null;
        }
        this._statusItems = [];
    }

    // Položky nabídky – stejné pro panel i pro HUD.
    _populateMenu(menu) {
        const statusItem = new PopupMenu.PopupMenuItem('Načítám…', {
            reactive: false,
            can_focus: false,
        });
        menu.addMenuItem(statusItem);
        this._statusItems.push(statusItem);

        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const refreshItem = new PopupMenu.PopupMenuItem('Obnovit teď');
        refreshItem.connect('activate', () => this._refresh());
        menu.addMenuItem(refreshItem);

        const testItem = new PopupMenu.PopupMenuItem('Vyzkoušet alarm');
        testItem.connect('activate', () => this._showAlert('low', '3,4', '↓'));
        menu.addMenuItem(testItem);

        const openItem = new PopupMenu.PopupMenuItem('Otevřít displej v prohlížeči');
        openItem.connect('activate', () => {
            Gio.AppInfo.launch_default_for_uri(PAGE_URL, null);
        });
        menu.addMenuItem(openItem);
    }

    // HUD kreslí přímo Shell (ne okno), takže drží nad okny a je na všech
    // plochách. Když je klikací, nese si vlastní nabídku s nastavením.
    _buildHud() {
        this._hud = new St.BoxLayout({style_class: 'glykemie-hud'});
        // GNOME 48+ nahradilo `vertical` za `orientation`
        if ('orientation' in this._hud)
            this._hud.orientation = Clutter.Orientation.VERTICAL;
        else
            this._hud.vertical = true;

        const row = new St.BoxLayout({x_align: Clutter.ActorAlign.CENTER});

        this._hudValue = new St.Label({
            text: '…',
            y_align: Clutter.ActorAlign.CENTER,
            style: `font-size: ${this._cfg.hudValueSize}px; font-weight: bold;`,
        });
        this._hudArrow = new St.Label({
            text: '',
            y_align: Clutter.ActorAlign.CENTER,
            style: `font-size: ${this._cfg.hudArrowSize}px; font-weight: bold; padding-left: 14px;`,
        });
        row.add_child(this._hudValue);
        row.add_child(this._hudArrow);
        this._hud.add_child(row);

        if (this._cfg.hudShowAge) {
            this._hudAge = new St.Label({
                text: '',
                x_align: Clutter.ActorAlign.CENTER,
                style: `font-size: ${this._cfg.hudAgeSize}px; color: ${COLOR_STALE}; padding-top: 6px;`,
            });
            this._hud.add_child(this._hudAge);
        }

        // Bez pozadí splyne s lištou, pod kterou sedí.
        if (!this._cfg.hudBackground)
            this._hud.set_style('background-color: transparent; border: none; padding: 0 8px;');

        this._hud.opacity = Math.round(this._cfg.hudOpacity * 255);

        // Reaktivní = chytá klik a otevírá nabídku. Nereaktivní = klik projde
        // skrz do okna (nebo do docku) pod HUD.
        this._hud.reactive = this._cfg.hudClickable;
        this._hud.track_hover = this._cfg.hudClickable;

        this._addChrome(this._hud);

        if (this._cfg.hudClickable)
            this._buildHudMenu();

        this._positionHud();
    }

    _buildHudMenu() {
        // Nabídka se otevírá nad HUD, protože ten sedí dole u okraje.
        this._hudMenu = new PopupMenu.PopupMenu(this._hud, 0.5, St.Side.BOTTOM);
        Main.uiGroup.add_child(this._hudMenu.actor);
        this._hudMenu.actor.hide();

        this._hudMenuManager = new PopupMenu.PopupMenuManager(this._hud);
        this._hudMenuManager.addMenu(this._hudMenu);

        this._populateMenu(this._hudMenu);

        this._hud.connect('button-press-event', () => {
            this._hudMenu.toggle();
            return Clutter.EVENT_STOP;
        });
    }

    _closeHudMenu() {
        if (this._hudMenu?.isOpen)
            this._hudMenu.close();
    }

    _destroyHud() {
        if (!this._hud)
            return;
        Main.layoutManager.removeChrome(this._hud);
        this._hud.destroy();
        this._hud = null;
        this._hudValue = null;
        this._hudArrow = null;
        this._hudAge = null;
    }

    // addTopChrome kreslí nad ostatní chrome, tedy i nad dock – jinak by
    // nám ho dock (taky chrome) mohl překrýt.
    _addChrome(actor) {
        if (typeof Main.layoutManager.addTopChrome === 'function')
            Main.layoutManager.addTopChrome(actor);
        else
            Main.layoutManager.addChrome(actor);
    }

    _monitorFor(index) {
        const monitors = Main.layoutManager.monitors;
        return index >= 0 && index < monitors.length
            ? monitors[index]
            : Main.layoutManager.primaryMonitor;
    }

    _positionHud() {
        if (!this._hud)
            return;

        const monitor = this._monitorFor(this._cfg.hudMonitor);
        if (!monitor)
            return;

        const [, width] = this._hud.get_preferred_width(-1);
        const [, height] = this._hud.get_preferred_height(width);
        const corner = this._cfg.hudCorner;

        const x = corner.endsWith('right')
            ? monitor.x + monitor.width - width - this._cfg.hudMarginX
            : monitor.x + this._cfg.hudMarginX;
        const y = corner.startsWith('bottom')
            ? monitor.y + monitor.height - height - this._cfg.hudMarginY
            : monitor.y + this._cfg.hudMarginY;

        this._hud.set_position(Math.round(x), Math.round(y));
    }

    _updateDisplay(valueText, arrow, ageText, color) {
        if (this._panel) {
            this._panel.label.set_text(`${valueText} ${arrow}`);
            this._panel.label.set_style(`color: ${color};`);
        }

        if (!this._hud)
            return;

        this._hudValue.set_text(valueText);
        this._hudValue.set_style(
            `font-size: ${this._cfg.hudValueSize}px; font-weight: bold; color: ${color};`
        );
        this._hudArrow.set_text(arrow);
        this._hudArrow.set_style(
            `font-size: ${this._cfg.hudArrowSize}px; font-weight: bold; padding-left: 14px; color: ${color};`
        );
        this._hudAge?.set_text(ageText);

        // šířka se mění podle délky čísla, tak HUD po každé změně přesadíme
        this._positionHud();
    }

    _setStatusText(text) {
        for (const item of this._statusItems)
            item.label.text = text;
    }

    // ---------- alarm ----------

    _showAlert(kind, valueText, arrow) {
        if (!this._cfg.alertEnabled)
            return;

        this._hideAlert();

        this._alert = new St.BoxLayout({style_class: 'glykemie-alert'});
        if ('orientation' in this._alert)
            this._alert.orientation = Clutter.Orientation.VERTICAL;
        else
            this._alert.vertical = true;

        const title = new St.Label({
            text: kind === 'low' ? 'NÍZKÁ GLYKEMIE' : 'VYSOKÁ GLYKEMIE',
            x_align: Clutter.ActorAlign.CENTER,
            style: `font-size: ${this._cfg.alertTitleSize}px; font-weight: bold; color: #fff;`,
        });

        const value = new St.Label({
            text: `${valueText} ${arrow}`,
            x_align: Clutter.ActorAlign.CENTER,
            style: `font-size: ${this._cfg.alertValueSize}px; font-weight: bold; color: #fff; padding: 10px 0;`,
        });

        const hint = new St.Label({
            text: 'klikni pro zavření',
            x_align: Clutter.ActorAlign.CENTER,
            style: 'font-size: 22px; color: rgba(255,255,255,0.75);',
        });

        this._alert.add_child(title);
        this._alert.add_child(value);
        this._alert.add_child(hint);

        this._alert.reactive = true; // tenhle chytá klik, aby šel zavřít
        this._alert.connect('button-press-event', () => {
            this._hideAlert();
            return Clutter.EVENT_STOP;
        });

        this._addChrome(this._alert);
        this._positionAlert();

        this._playAlertSound();
        if (this._cfg.alertSoundRepeatSeconds > 0) {
            this._alertSoundId = GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                this._cfg.alertSoundRepeatSeconds,
                () => {
                    this._playAlertSound();
                    return GLib.SOURCE_CONTINUE;
                }
            );
        }

        if (this._cfg.alertPulse) {
            let dim = false;
            this._alertPulseId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 600, () => {
                dim = !dim;
                this._alert?.set_opacity(dim ? 150 : 255);
                return GLib.SOURCE_CONTINUE;
            });
        }

        if (this._cfg.alertAutoHideMinutes > 0) {
            this._alertHideId = GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                this._cfg.alertAutoHideMinutes * 60,
                () => {
                    this._alertHideId = 0;
                    this._hideAlert();
                    return GLib.SOURCE_REMOVE;
                }
            );
        }
    }

    _positionAlert() {
        if (!this._alert)
            return;

        const monitor = this._monitorFor(this._cfg.alertMonitor);
        if (!monitor)
            return;

        const [, width] = this._alert.get_preferred_width(-1);
        const [, height] = this._alert.get_preferred_height(width);

        this._alert.set_position(
            Math.round(monitor.x + (monitor.width - width) / 2),
            Math.round(monitor.y + (monitor.height - height) / 2)
        );
    }

    _hideAlert() {
        for (const id of ['_alertPulseId', '_alertSoundId', '_alertHideId']) {
            if (this[id]) {
                GLib.source_remove(this[id]);
                this[id] = 0;
            }
        }
        if (this._alert) {
            Main.layoutManager.removeChrome(this._alert);
            this._alert.destroy();
            this._alert = null;
        }
    }

    _playAlertSound() {
        if (!this._cfg.alertSound)
            return;
        try {
            global.display
                .get_sound_player()
                .play_from_theme(this._cfg.alertSoundName, 'Glykemie alarm', null);
        } catch (e) {
            try {
                Gio.Subprocess.new(
                    ['canberra-gtk-play', '-i', this._cfg.alertSoundName],
                    Gio.SubprocessFlags.NONE
                );
            } catch (e2) {
                logError(e2, 'Glykemie: zvuk se nepodařilo přehrát');
            }
        }
    }

    // ---------- data ----------

    _refresh() {
        const message = Soup.Message.new('GET', API_URL);
        if (!message) {
            this._onError('neplatná URL');
            return;
        }
        message.request_headers.append('cache-control', 'no-cache');

        this._session.send_and_read_async(
            message,
            GLib.PRIORITY_DEFAULT,
            this._cancellable,
            (session, result) => {
                try {
                    const bytes = session.send_and_read_finish(result);
                    if (message.get_status() !== Soup.Status.OK)
                        throw new Error(`HTTP ${message.get_status()}`);

                    const text = new TextDecoder('utf-8').decode(bytes.get_data());
                    const data = JSON.parse(text);
                    if (data.error)
                        throw new Error(data.error);

                    this._lastData = data;
                    this._onData(data);
                } catch (e) {
                    if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        this._onError(e.message ?? String(e));
                }
            }
        );
    }

    _onData(data) {
        this._errorCount = 0;
        this._errorNotified = false;

        const mmol = data.mmol;
        const arrow = data.trendSymbol ?? '';
        const age = this._minutesAgo(data.timestamp);
        const stale = age !== null && age > this._cfg.staleMinutes;
        const outOfRange = mmol < this._cfg.lowMmol || mmol > this._cfg.highMmol;

        let ageText;
        if (age === null)
            ageText = 'čas neznámý';
        else if (age <= 1)
            ageText = 'právě teď';
        else
            ageText = `před ${age} min`;

        this._updateDisplay(
            this._formatValue(mmol),
            arrow,
            ageText,
            stale ? COLOR_STALE : outOfRange ? COLOR_ALERT : COLOR_OK
        );
        this._setStatusText(`${this._formatValue(mmol)} mmol/l ${arrow} · ${ageText}`);

        // Ze starých dat se neupozorňuje – hodnota už nemusí platit.
        if (!stale)
            this._maybeNotify(mmol, arrow);
    }

    _onError(message) {
        this._errorCount++;

        // Při výpadku sítě nemažeme poslední známou hodnotu – jen ji
        // ztlumíme. Prázdný displej je pro letmý pohled horší než stará
        // hodnota, u které je vidět, že je stará.
        if (this._lastData) {
            this._updateDisplay(
                this._formatValue(this._lastData.mmol),
                this._lastData.trendSymbol ?? '',
                'nedostupné',
                COLOR_STALE
            );
        } else {
            this._updateDisplay('–', '', 'nedostupné', COLOR_STALE);
        }
        this._setStatusText(`Chyba: ${message}`);

        // Jeden rychlý pokus navíc, ať se po krátkém výpadku nečeká
        // celý refresh interval.
        if (!this._retryId) {
            this._retryId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 10, () => {
                this._retryId = 0;
                this._refresh();
                return GLib.SOURCE_REMOVE;
            });
        }

        if (this._errorCount >= this._cfg.errorsBeforeNotify && !this._errorNotified) {
            this._errorNotified = true;
            this._notify(
                'Glykemie nedostupná',
                `Worker neodpovídá už ${this._errorCount} pokusů: ${message}`,
                false
            );
        }
    }

    _maybeNotify(mmol, arrow) {
        let state = 'ok';
        if (mmol < this._cfg.lowMmol)
            state = 'low';
        else if (mmol > this._cfg.highMmol)
            state = 'high';

        if (state === 'ok') {
            this._notifyState = 'ok';
            this._hideAlert(); // hodnota se vrátila do normálu
            return;
        }

        const now = GLib.get_monotonic_time() / 1000000;
        const changed = state !== this._notifyState;
        const cooled = now - this._lastNotifyTime >= this._cfg.notifyCooldownMinutes * 60;
        if (!changed && !cooled)
            return;

        const valueText = this._formatValue(mmol);
        if (state === 'low')
            this._notify('Nízká glykemie', `${valueText} mmol/l ${arrow}`, true);
        else
            this._notify('Vysoká glykemie', `${valueText} mmol/l ${arrow}`, false);

        this._showAlert(state, valueText, arrow);

        this._notifyState = state;
        this._lastNotifyTime = now;
    }

    // API notifikací se mezi GNOME 45 a 46 změnilo (poziční argumenty ->
    // objekt). Zkusíme novější tvar a při chybě spadneme na starý.
    _notify(title, body, critical) {
        const urgency = critical
            ? MessageTray.Urgency.CRITICAL
            : MessageTray.Urgency.HIGH;

        try {
            if (!this._notifySource) {
                this._notifySource = new MessageTray.Source({
                    title: 'Glykemie',
                    iconName: 'utilities-system-monitor-symbolic',
                });
                this._notifySource.connect('destroy', () => {
                    this._notifySource = null;
                });
                Main.messageTray.add(this._notifySource);
            }

            const notification = new MessageTray.Notification({
                source: this._notifySource,
                title,
                body,
                urgency,
            });
            this._notifySource.addNotification(notification);
        } catch (e) {
            logError(e, 'Glykemie: nové API notifikací selhalo, zkouším starší');
            try {
                if (!this._notifySource) {
                    this._notifySource = new MessageTray.Source(
                        'Glykemie',
                        'utilities-system-monitor-symbolic'
                    );
                    this._notifySource.connect('destroy', () => {
                        this._notifySource = null;
                    });
                    Main.messageTray.add(this._notifySource);
                }

                const notification = new MessageTray.Notification(
                    this._notifySource,
                    title,
                    body
                );
                notification.setUrgency(urgency);
                this._notifySource.showNotification(notification);
            } catch (e2) {
                logError(e2, 'Glykemie: upozornění se nepodařilo zobrazit');
            }
        }
    }

    _formatValue(mmol) {
        return mmol.toFixed(1).replace('.', ',');
    }

    _minutesAgo(timestamp) {
        // LibreLinkUp posílá např. "9/9/2026 9:43:12 PM"
        const t = Date.parse(timestamp);
        if (isNaN(t))
            return null;
        return Math.round((Date.now() - t) / 60000);
    }

    destroy() {
        for (const id of ['_timeoutId', '_retryId']) {
            if (this[id]) {
                GLib.source_remove(this[id]);
                this[id] = 0;
            }
        }
        this._hideAlert();

        this._cancellable?.cancel();
        this._cancellable = null;
        this._session?.abort();
        this._session = null;
        this._notifySource?.destroy();
        this._notifySource = null;

        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = 0;
        }

        this._destroyUi();
    }
}

export default class GlykemieExtension extends Extension {
    enable() {
        this._monitor = new GlykemieMonitor(loadConfig(this.dir), this.uuid);

        // config.json sledujeme, ať jde nastavení měnit bez odhlašování
        this._configFile = this.dir.get_child('config.json');
        this._configMonitor = this._configFile.monitor_file(
            Gio.FileMonitorFlags.NONE,
            null
        );
        this._configMonitor.connect('changed', () => {
            // editor může soubor přepsat na několik kroků, tak to zdržíme
            if (this._reloadId)
                GLib.source_remove(this._reloadId);
            this._reloadId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
                this._reloadId = 0;
                this._monitor?.applyConfig(loadConfig(this.dir));
                return GLib.SOURCE_REMOVE;
            });
        });
    }

    disable() {
        if (this._reloadId) {
            GLib.source_remove(this._reloadId);
            this._reloadId = 0;
        }
        this._configMonitor?.cancel();
        this._configMonitor = null;
        this._configFile = null;

        this._monitor?.destroy();
        this._monitor = null;
    }
}
