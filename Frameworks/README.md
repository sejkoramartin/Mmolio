# Frameworks

`ConnectIQ.xcframework` belongs here.

It is **not** in the repository: Garmin distributes it from their developer portal behind
a sign-in, and redistributing it is not ours to do. `.gitignore` keeps it out.

Without it the app builds and runs normally — `GarminTransportFactory` returns a stand-in
transport that reports the SDK as absent. Nothing else changes.

See `garmin/README.md` for how to obtain and install it.
