# Pulse signing
Pulse uses `local.pulse.monitor` at `build/Pulse.app`.
`scripts/bundle.sh` defaults to ad-hoc signing; FDA resets after each rebuild.
For stable signing, supply `SIGN_IDENTITY` or `--sign-identity <name-or-hash>`.
The flag takes precedence; gitignored `scripts/local.env` may export the variable.
Names must resolve uniquely; certificate hashes and self-signed identities are accepted.
A staged copy is signed and verified before the current bundle is replaced.
Validation/signing failure preserves the current app; backups remain under `build/`.
No keychain or account settings are changed.
A stable certificate signature keeps its requirement across rebuilds.
Verify `codesign --verify --deep --strict build/Pulse.app` and
`codesign -d -r- build/Pulse.app` after two builds; compare requirements.
Enable the app in System Settings → Privacy & Security → Full Disk Access,
then quit and relaunch. FDA is optional. If Pulse cannot open the TCC database,
it shows a one-time prompt with Open Settings and Don't ask again. An ad-hoc
rebuild can drop the grant.
Restricted hosts may lack signing-key access; verify on the desktop host.
