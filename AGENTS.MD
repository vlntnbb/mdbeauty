# AGENTS.MD

## Build Rule

After every project change, update the app executable in `dist` before reporting the work as complete.

Use:

```bash
./scripts/build-app.sh
```

The expected executable is:

```text
dist/MDbeaty.app/Contents/MacOS/MDbeaty
```

If the incremental build reports success but the executable in `dist` was not physically refreshed, run a clean rebuild and recreate the app bundle:

```bash
swift package clean
./scripts/build-app.sh
```
