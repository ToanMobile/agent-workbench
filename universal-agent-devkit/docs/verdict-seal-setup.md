# Verdict seal: one-time owner setup (#632 B)

Until `/private/etc/devkit/verdict-seal.pub` exists, nothing changes: edited-test approval keeps trusting the antigravity-pm
record. After you install it, an Antigravity audit pass counts only when it has a seal signed by a key that the agent's uid
cannot read.

You do this once, with `sudo`. No agent can run these steps. `OWNER` is your login (`alex`). `KIT` is the kit folder
(`universal-agent-devkit` in agent-workbench).

```bash
# 1. A separate uid that owns the key (no login shell, hidden)
sudo sysadminctl -addUser _devkitseal -fullName "DevKit verdict seal" -shell /usr/bin/false -home /var/devkitseal -roleAccount
sudo mkdir -p /var/devkitseal/Library/Keychains && sudo chown -R _devkitseal /var/devkitseal && sudo chmod 700 /var/devkitseal

# 2. Root-owned programs
sudo mkdir -p /private/etc/devkit/libexec
sudo swiftc -O -o /private/etc/devkit/libexec/verdict-signer "$KIT/libexec/verdict-signer.swift"
sudo install -o root -g wheel -m 755 "$KIT/libexec/verdict-seal-audit" /private/etc/devkit/libexec/verdict-seal-audit
sudo install -o root -g wheel -m 755 "$(readlink -f ~/.local/bin/agy)" /private/etc/devkit/libexec/agy
sudo chown root:wheel /private/etc/devkit/libexec/verdict-signer && sudo chmod 755 /private/etc/devkit/libexec/verdict-signer

# 3. Keychain of _devkitseal (empty password: the uid and mode 600 are the boundary), and the key (ACL: the signer only)
sudo -u _devkitseal -H security create-keychain -p "" /var/devkitseal/Library/Keychains/seal.keychain-db
sudo -u _devkitseal -H security set-keychain-settings /var/devkitseal/Library/Keychains/seal.keychain-db
sudo chmod 600 /var/devkitseal/Library/Keychains/seal.keychain-db
sudo -u _devkitseal -H /private/etc/devkit/libexec/verdict-signer --generate | sudo tee /private/etc/devkit/verdict-seal.pub
sudo chown root:wheel /private/etc/devkit/verdict-seal.pub && sudo chmod 644 /private/etc/devkit/verdict-seal.pub

# 4. sudoers: OWNER may run ONLY the audit entry as _devkitseal, without a password
echo "OWNER ALL=(_devkitseal) NOPASSWD: /private/etc/devkit/libexec/verdict-seal-audit" | sudo tee /etc/sudoers.d/devkit-verdict-seal
sudo chmod 440 /etc/sudoers.d/devkit-verdict-seal && sudo visudo -c

# 5. Sign agy in for _devkitseal (it audits under that HOME). agy keeps its login in the login keychain, so create one with
#    an empty password that the audit can unlock with no GUI session.
sudo -u _devkitseal -H security create-keychain -p "" /var/devkitseal/Library/Keychains/login.keychain-db
sudo -u _devkitseal -H security default-keychain -s /var/devkitseal/Library/Keychains/login.keychain-db
sudo -u _devkitseal -H /private/etc/devkit/libexec/agy
```

Checks:

```bash
# Every dir above the key and the programs must be root-owned and not group/other writable (else the agent could swap them)
stat -f "%N %Su %Sp" / /private /private/etc /private/etc/devkit /private/etc/devkit/libexec
python3 "$KIT/bin/verdict_seal.py" status                       # seal mode: on
sudo -u _devkitseal -H /private/etc/devkit/libexec/verdict-signer --pubkey | diff - /private/etc/devkit/verdict-seal.pub
/private/etc/devkit/libexec/verdict-signer --pubkey; echo "exit $? (must fail: your uid has no key)"
python3 "$KIT/bin/verdict_seal.py" request --repo . --head "$(git rev-parse HEAD)"   # one real sealed audit
```

Daily use (agents): after an Antigravity audit pass on a PR head, run
`python3 <kit>/bin/verdict_seal.py request --repo . --head <sha40>` (`<kit>` = `universal-agent-devkit` here, `.agents/devkit` in app repos). The seal lands in
`~/.antigravity-pm/seals/<head>.json`. Gates read it from there.

Emergency off switch: `sudo rm /private/etc/devkit/verdict-seal.pub`. No environment variable can turn seal mode off.

Known limits:
- The seal binds content (head, tree, signed base and edited), not a PM task id. Task ids are only pointers to a record, and a
  seal for the right content approves under any task id. A seal for other content never does.
- agy runs as `_devkitseal`, the same uid as the signer, but never inside a checkout. Its cwd holds only data files
  (`.seal/diff.patch`, `name-status.txt`, and each changed file as `<path>.seal-data`), so no project config of the PR (MCP servers,
  hooks, AGENTS.md/GEMINI.md) reaches it, and `--print` without `--dangerously-skip-permissions` runs no shell. The remaining
  risk: a prompt injection in the diff can get a wrong pass signed for that content. A compromised agy binary could run the signer.
  Upgrade path: run agy as a third uid that cannot exec the signer.
- Ledger in `~_devkitseal/verdict-ledger` (out of the agent's reach): the FIRST verdict for a content (base + blobs of the
  edited paths) is final, a re-run returns it, and two runs on one content cannot race (O_EXCL lock). Each new content of the same
  change (base + edited paths) is one more attempt, signed into the seal; a pass after more than 3 attempts does not count. A
  corrupt record counts as fail. The REVISE check on task.json in the gate is advisory only, because task.json is agent-writable.
- agy's work dir and TMPDIR are in `~_devkitseal/verdict-work` (0700), never the shared /tmp.
- The key is machine-wide: installing it turns seal mode on for every repo on this Mac at once. Trunk is found as
  origin/main|master|trunk (then the local branch). A repo whose PRs target another branch (develop, for example) would have
  every edited test refused (fail closed) until both sides read its trunk.
- A local post-fix-gate trusts local trunk refs. The merge gate uses origin/main fetched from GitHub.
