# Security

## Supported versions

Only the latest release gets fixes.

## Reporting a vulnerability

Please report it privately: open the repository's **Security** tab and click **Report a vulnerability**. Do not open a public issue for it.

Useful things to include: what an attacker could do, the steps to reproduce, your macOS version and the HapticPad version.

## What counts

HapticPad reads trackpad contacts and drives the trackpad's actuator through Apple's private MultitouchSupport framework. When keyboard sounds are on, it also listens to key presses with a listen-only event tap and only looks at which kind of key was pressed. It makes no network requests. Anything that lets someone learn what you type through HapticPad, run code through the app, or make it reach the network is in scope.
