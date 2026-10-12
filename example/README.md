# frontface_chat_example

Demo host for the `frontface_chat` package (chat UI, maps, call-screen preview).

## Incoming call branding (reference assets)

When wiring inbound CallKit / ConnectionService (see repo `CALLS_INTEGRATION.md` §4.3.1):

| Asset | Use |
|---|---|
| `ios/Runner/Assets.xcassets/CallKitLogo.imageset/` | iOS CallKit template icon (`IOSParams.iconName: 'CallKitLogo'`) — also set on the VoIP `AppDelegate` path |
| `assets/images/call_logo.png` | Android `AndroidParams.logoUrl` with `isShowLogo: true` |

Replace both with your brand mark before shipping. Prefer a silhouette / alpha template for `CallKitLogo` (CallKit tints it).
