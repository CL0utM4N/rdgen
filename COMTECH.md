# Comtech IT fork of rdgen

This fork is only used for its GitHub Actions workflows. Builds are started
from the Client Builder page of the Comtech RustDesk API
(CL0utM4N/rustdesk-api, branch client-builder), which also serves the
callbacks the workflows make. The rdgen web app itself is not deployed.

Repository secrets:

- `GENURL`: `https://rd.comtechit.au/api/clientgen`
- `ZIP_PASSWORD`: same value as `RUSTDESK_API_CLIENTGEN_ZIP_PASSWORD` on the API server

The "update docker image" workflow is disabled because the rdgen web app is not used.

Pull upstream changes with:

    git fetch upstream && git merge upstream/master
