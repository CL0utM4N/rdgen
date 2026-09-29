# Console preview

Runs the Comtech console in a browser, without building the RustDesk client,
for checking pages while working on them.

The API only answers the console from its own address, so build it to be
served by an API at `/_admin/`:

    flutter build web --base-href /_admin/ --no-web-resources-cdn

and copy `build/web` to the API's `resources/admin` folder (a test server,
never the live one). Connect buttons show an alert instead of connecting.
