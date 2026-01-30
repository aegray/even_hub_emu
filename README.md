# even_hub_emu

Flutter-based emulator for the Even Hub sdk (https://www.npmjs.com/package/@evenrealities/even_hub_sdk)

## What this includes
- A `flutter_inappwebview` host that loads a **local** `index.html`.
- A glass display renderer that mirrors the EvenHub container API (list/text/image).
- A small, easy-to-edit bridge host (`EvenAppBridgeHost`) that routes messages between JS and Flutter in order to implement an emulated Evenhub api.
- Log console and webpage error logs

## Usage
After building and running, the app starts with a default index.html that demonstrates various sdk event handling.

To load your own index.html, click the folder/open index button and pick a file.  Paths (for example javascript src paths) are relative to the directory of the index.html.

If you edit the index.html or any referenced code, you can click the reload button to reload the page and reinit the emulator.

There's an example app in example/demo_v1 that is mostly copied from the sdk examples.

## Accuracy
The api mostly works as you'd expect, however I'm making some guesses at how it will actually work on a phone based on the docs.  Please provide any feedback on what's off and I'll fix.

Biggest known issues:
* The event model isn't completely clear to me yet (how do I trigger a list event?  What is a text event?) so the events / interaction with the glasses are definitely wrong
* Actual image data is still untested (working on that)


## Bootstrap (first time)
If you need platform folders (`android/`, `ios/`, etc.), run:

```
flutter create .
```

This keeps `lib/` and `pubspec.yaml` intact while generating platform scaffolding.
## Key Flutter files
- `lib/bridge/even_app_bridge.dart`
  - Implements the EvenHub API surface (`evenAppMessage` handler).
  - Emits device status + evenHub events back to JS.
- `lib/bridge/event_pump.dart`
  - Central place to tune *when* events are pushed to JS.
- `lib/glasses/glasses_model.dart`
  - Models + parsing of container payloads.
- `lib/glasses/glasses_screen.dart`
  - Renders containers and lets you click list/text to fire events.
- `lib/main.dart`
  - Wires WebView + glasses UI together and injects the JS handler.

## Bridge message format (JS -> Flutter)
```js
{
  type: 'call_even_app_method',
  method: 'createStartUpPageContainer',
  data: { /* payload */ }
}
```

## Push events (Flutter -> JS)
```js
{
  type: 'listen_even_app_data',
  method: 'evenHubEvent',
  data: {
    type: 'listEvent',
    jsonData: { /* event payload */ }
  }
}
```

## Notes
- `createStartUpPageContainer` is enforced to run once.
- At most 4 containers are allowed; exactly one must have `isEventCapture=1`.
- Images accept `imageData` (base64 or `number[]`). Invalid images are shown with a placeholder.
