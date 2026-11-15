# Verdict seal: one-time owner setup (#632 B)

Until `/usr/local/etc/devkit/verdict-seal.pub` exists, nothing changes: edited-test approval keeps trusting the antigravity-pm
record. After you install it, an Antigravity audit pass counts only when it has a seal signed by a key that the agent's uid
cannot read.

You do this once, with `sudo`. No agent can run these steps. `OWNER` is your login (`alex`). `KIT` is the kit folder
(`universal-agent-devkit` in agent-workbench).

```bash
# 1. A separate uid that owns the key (no login shell, hidden)
sudo sysadminctl -addUser _devkitseal -fullName "DevKit verdict seal" -shell /usr/bin/false -home /var/devkitseal -roleAccount
sudo mkdir -p /var/devkitseal/Library/Keychains && sudo chown -R _devkitseal /var/devkitseal && sudo chmod 700 /var/devkitseal

# 2. Root-owned programs
sudo mkdir -p /usr/local/libexec/devkit /usr/local/etc/devkit
sudo swiftc -O -o /usr/local/libexec/devkit/verdict-signer "$KIT/libexec/verdict-signer.swift"
sudo install -o root -g wheel -m 755 "$KIT/libexec/verdict-seal-audit" /usr/local/libexec/devkit/verdict-seal-audit
sudo install -o root -g wheel -m 755 "$(readlink -f ~/.local/bin/agy)" /usr/local/libexec/devkit/agy
sudo chown root:wheel /usr/local/libexec/devkit/verdict-signer && sudo chmod 755 /usr/local/libexec/devkit/verdict-signer

# 3. Keychain of _devkitseal (empty password: the uid and mode 600 are the boundary), and the key (ACL: the signer only)
sudo -u _devkitseal -H security create-keychain -p "" /var/devkitseal/Library/Keychains/seal.keychain-db
sudo -u _devkitseal -H security set-keychain-settings /var/devkitseal/Library/Keychains/seal.keychain-db
sudo chmod 600 /var/devkitseal/Library/Keychains/seal.keychain-db
sudo -u _devkitseal -H /usr/local/libexec/devkit/verdict-signer --generate | sudo tee /usr/local/etc/devkit/verdict-seal.pub
sudo chown root:wheel /usr/local/etc/devkit/verdict-seal.pub && sudo chmod 644 /usr/local/etc/devkit/verdict-seal.pub

# 4. sudoers: OWNER may run ONLY the audit entry as _devkitseal, without a password
echo "OWNER ALL=(_devkitseal) NOPASSWD: /usr/local/libexec/devkit/verdict-seal-audit" | sudo tee /etc/sudoers.d/devkit-verdict-seal
sudo chmod 440 /etc/sudoers.d/devkit-verdict-seal && sudo visudo -c

# 5. Sign agy in for _devkitseal (it audits under that HOME). agy keeps its login in the login keychain, so create one with
#    an empty password that the audit can unlock with no GUI session.
sudo -u _devkitseal -H security create-keychain -p "" /var/devkitseal/Library/Keychains/login.keychain-db
sudo -u _devkitseal -H security default-keychain -s /var/devkitseal/Library/Keychains/login.keychain-db
sudo -u _devkitseal -H /usr/local/libexec/devkit/agy
```

Checks:

```bash
# Every dir above the key and the programs must be root-owned and not group/other writable (else the agent could swap them)
stat -f '%N %Su %Sp' / /usr /usr/local /usr/local/etc /usr/local/etc/devkit /usr/local/libexec /usr/local/libexec/devkit
python3 "$KIT/bin/verdict_seal.py" status                       # seal mode: on
sudo -u _devkitseal -H /usr/local/libexec/devkit/verdict-signer --pubkey | diff - /usr/local/etc/devkit/verdict-seal.pub
/usr/local/libexec/devkit/verdict-signer --pubkey; echo "exit $? (must fail: your uid has no key)"
python3 "$KIT/bin/verdict_seal.py" request --repo . --head "$(git rev-parse HEAD)"   # one real sealed audit
```

Daily use (agents): after an Antigravity audit pass on a PR head, run
`python3 universal-agent-devkit/bin/verdict_seal.py request --repo . --head <sha40>`. The seal lands in
`~/.antigravity-pm/seals/<head>.json`. Gates read it from there.

Emergency off switch: `sudo rm /usr/local/etc/devkit/verdict-seal.pub`. No environment variable can turn seal mode off.

Known limits:
- The seal binds content (head, tree, signed base and edited), not a PM task id. Task ids are only pointers to a record, and a
  seal for the right content approves under any task id. A seal for other content never does.
- agy runs as `_devkitseal`, the same uid as the signer. A prompt injection in the audited diff can therefore get a pass signed.
  It cannot get anything else signed, because the payload is built by the helper. This is the same exposure as an unsigned
  audit today.
- A local post-fix-gate trusts local trunk refs. The merge gate uses origin/main fetched from GitHub.
