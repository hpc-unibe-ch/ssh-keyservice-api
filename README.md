# SSH Keyservice API

A FastAPI for centralised management of SSH Keys protected through OpenID Connect via Azure.
Users manage their SSH keys via a web portal ([ssh-keyservice](https://github.com/hpc-unibe-ch/ssh-keyservice)) - similar to GitHub - instead of traditionally in `~/.ssh/authorised_keys`.
On servers connected to the keyservice, the `sshd` server performs an API query using `AuthorisedKeysCommand` to retrieve the keys stored by the user. The API (this repo) returns a raw response in the same format as GitHub keys.

## Background
Traditionally, users generate an SSH key and transfer the public key to a server using `ssh-copy-id` or `scp`. This process usually only requires a password or an already stored key for authentication. This approach harbours some security risks:
- It does not ensure that users actually deposit their own key. Instead, they could consciously or unconsciously use the public key of a third party to share an account.
- If the file with the stored keys is inadvertently inadequately protected, third parties could add their own keys without authorisation and thus gain access.

This app is designed to address these problems. A secure web front end allows users to manage their SSH keys, while additional security mechanisms prevent misuse:
- Possibility to enforce multi-factor authentication (MFA) when accessing the keyservice frontend. This significantly increases security.
- Challenge-response verification to ensure that users actually have the complete key pair (private and public key) before the key is accepted.

## Repositories
[ssh-keyservice-api (this repo)](https://github.com/hpc-unibe-ch/ssh-keyservice-api) - Backend API
[ssh-keyservice](https://github.com/hpc-unibe-ch/ssh-keyservice) - Frontend Webapp

