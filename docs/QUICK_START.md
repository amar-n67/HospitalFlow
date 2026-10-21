# Run HospitalFlow

The project uses the same clear root-level .NET organization as the reference AmarShowsBook application. The project file and `Program.cs` are at the repository root, alongside `Controllers`, `Models`, `Data`, `Services`, `Helpers`, `Database` and `wwwroot`.

## Start the existing installation

```sh
cd /Users/amarnath/Documents/VS-Code_Projects/HospitalFlow
./hospitalflow run
```

Open **http://localhost:5136**. Keep that terminal running. Press **Ctrl+C** to stop the application. This does not stop your shared PostgreSQL server on port 5432.

The launcher checks PostgreSQL, builds and runs the application, then watches for new Git commits. When a commit advances the version, it rebuilds and restarts the local server automatically. Failed builds leave the previous server running. The frontend checks the running version every 15 seconds without discarding open forms. Existing private configuration is now in root-level `appsettings.Local.json`, and the provisioning settings remain `.local/database.json`. Existing data, passwords and migration history are preserved. The launcher does not create a database, reset accounts or run migrations automatically.

Standard .NET commands work directly from the root as well:

```sh
dotnet run
```

For an explicit launch profile:

```sh
dotnet run --launch-profile http
```

## Commands

| Command | Purpose |
|---|---|
| `./hospitalflow help` | Show supported commands |
| `./hospitalflow run` | Check PostgreSQL, build/start on port 5136 and rebuild/restart after new Git commits |
| `./hospitalflow watch` | Start development mode with code-change reload |
| `./hospitalflow build` | Restore/build the root project |
| `./hospitalflow test` | Build, frontend tests, temporary Git version tests and isolated PostgreSQL regression suite |
| `./hospitalflow status` | Check the configured database service |
| `./hospitalflow verify` | Check installed database integrity, security and migration checksums |
| `./hospitalflow backup` | Save a private PostgreSQL backup |
| `./hospitalflow migrate` | Build, apply pending migrations with the private owner account and refresh restricted grants |
| `./hospitalflow version` | Print the checkout's commit-managed version |

`migrate` is an explicit administration command; run it only when deploying pending migrations and preferably after a backup. It preserves populated records and applied migrations. Tests use disposable databases and do not reset the installed database.

The launcher resolves its own directory, so this also works from elsewhere:

```sh
/Users/amarnath/Documents/VS-Code_Projects/HospitalFlow/hospitalflow run
```

## IDE

Open `HospitalFlow.sln`, or open the repository folder in VS Code. Use **Terminal → Run Task → HospitalFlow: run**. **HospitalFlow: build** is the default build task. The debugger configuration **HospitalFlow (.NET, port 5136)** starts the root application's compiled DLL with Development settings; it requires the usual C# debugging extension.

Run only one server on port 5136. If the application is already running, use its existing browser window or stop its terminal with Ctrl+C before starting a second instance. The launcher does not kill other processes or choose an unexpected port.

## Requirements and another machine

Use the installed .NET 10 SDK, Python 3 and PostgreSQL client tools. Node.js is needed for frontend tests. PostgreSQL 17 must be available for database checks and isolated integration tests. The repository does not include or expose passwords. On another machine, provide `appsettings.Local.json` or `ConnectionStrings__HospitalFlow`, provision the restricted runtime account and apply migrations using the [database guide](DATABASE.md). Local setup for this existing installation is already complete.

Database-backed local email/SMS deliveries remain under `.local/mail` and `.local/sms`. These are private delivery artifacts, not application data sources.

Docker paths have also been updated for the root project. Production hosting still requires the HTTPS, mail and key-encryption configuration described in [Deployment](DEPLOYMENT.md); the local development launcher does not change those requirements.

Plain `dotnet run` and an attached debugger do not use the commit supervisor; rebuild/restart those sessions manually, or use `./hospitalflow run` for automatic local release updates. A Git push does not deploy a remote production host.
