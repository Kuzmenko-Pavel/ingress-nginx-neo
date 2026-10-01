# External OAUTH Authentication

### Overview

The `auth-url` and `auth-signin` annotations allow you to use an external
authentication provider to protect your Ingress resources.

### Key Detail

This functionality is enabled by deploying multiple Ingress objects for a single host.
One Ingress object has no special annotations and handles authentication.

Other Ingress objects can then be annotated in such a way that require the user to
authenticate against the first Ingress's endpoint, and can redirect `401`s to the
same endpoint.

Sample:

```yaml
...
metadata:
  name: application
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://$host/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$host/oauth2/start?rd=$escaped_request_uri"
...
```

### Example: OAuth2 Proxy

This example will show you how to deploy [OAuth2 Proxy](https://github.com/oauth2-proxy/oauth2-proxy)
into a Kubernetes cluster and use it to protect an application (the [test HTTP service](../../PREREQUISITES.md#test-http-service) `http-svc`) using GitHub as the OAuth2 provider.

#### Prepare

1. Deploy the [test HTTP service](../../PREREQUISITES.md#test-http-service) `http-svc` in the `default` namespace
   and create a TLS Secret for your host (see [TLS certificates](../../PREREQUISITES.md#tls-certificates))

2. Create a [custom GitHub OAuth application](https://github.com/settings/applications/new)

    ![Register OAuth2 Application](images/register-oauth-app.png)

    - Homepage URL is the FQDN in the Ingress rule, like `https://foo.bar.com`
    - Authorization callback URL is the same as the base FQDN plus `/oauth2/callback`, like `https://foo.bar.com/oauth2/callback`

    ![Register OAuth2 Application](images/register-oauth-app-2.png)

3. Configure values in the file [`oauth2-proxy.yaml`](oauth2-proxy.yaml) with the values:

    - OAUTH2_PROXY_CLIENT_ID with the github `<Client ID>`
    - OAUTH2_PROXY_CLIENT_SECRET with the github `<Client Secret>`
    - OAUTH2_PROXY_COOKIE_SECRET with value of `dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d -- '\n' | tr -- '+/' '-_'; echo`
    - (optional, but recommended) OAUTH2_PROXY_GITHUB_USERS with GitHub usernames to allow to login
    - `__INGRESS_HOST__` with a valid FQDN (e.g. `foo.bar.com`)
    - `__INGRESS_SECRET__` with a Secret with a valid SSL certificate

4. Deploy the oauth2 proxy and the ingress rules by running:

    ```console
    $ kubectl apply -f oauth2-proxy.yaml
    ```

#### Test

Test the integration by accessing the configured URL, e.g. `https://foo.bar.com`

![Register OAuth2 Application](images/github-auth.png)

![GitHub authentication](images/oauth-login.png)

After a successful login, the request is forwarded to `http-svc`, which echoes the request details.


### Example: Vouch Proxy

This example will show you how to deploy [Vouch Proxy](https://github.com/vouch/vouch-proxy)
into a Kubernetes cluster and use it to protect an application (the [test HTTP service](../../PREREQUISITES.md#test-http-service) `http-svc`) using GitHub as the OAuth2 provider.

#### Prepare

1. Deploy the [test HTTP service](../../PREREQUISITES.md#test-http-service) `http-svc` in the `default` namespace
   and create a TLS Secret for your host (see [TLS certificates](../../PREREQUISITES.md#tls-certificates))

2. Create a [custom GitHub OAuth application](https://github.com/settings/applications/new)

    ![Register OAuth2 Application](images/register-oauth-app.png)

    - Homepage URL is the FQDN in the Ingress rule, like `https://foo.bar.com`
    - Authorization callback URL is the same as the base FQDN plus `/oauth2/auth`, like `https://foo.bar.com/oauth2/auth`

    ![Register OAuth2 Application](images/register-oauth-app-2.png)

3. Configure Vouch Proxy values in the file [`vouch-proxy.yaml`](vouch-proxy.yaml) with the values:

    - VOUCH_COOKIE_DOMAIN with value of `<Ingress Host>`
    - OAUTH_CLIENT_ID with the github `<Client ID>`
    - OAUTH_CLIENT_SECRET with the github `<Client Secret>`
    - (optional, but recommended) VOUCH_WHITELIST with GitHub usernames to allow to login
    - `__INGRESS_HOST__` with a valid FQDN (e.g. `foo.bar.com`)
    - `__INGRESS_SECRET__` with a Secret with a valid SSL certificate

4. Deploy Vouch Proxy and the ingress rules by running:

    ```console
    $ kubectl apply -f vouch-proxy.yaml
    ```

#### Test

Test the integration by accessing the configured URL, e.g. `https://foo.bar.com`

![Register OAuth2 Application](images/github-auth.png)

![GitHub authentication](images/oauth-login.png)

After a successful login, the request is forwarded to `http-svc`, which echoes the request details.
