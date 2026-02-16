# Feedback and thoughts on EvenHub

## Easy Improvement (with fix examples): Cross origin restrictions
Allowing more cross site operations would make building apps much easier.  The app currently obeys standard rules, meaning I can load images or use websockets cross origin, however the following fail:
* fetch from another domain
* fetch from a mixed mode (fetching https from http or vice versa)
* fetching from a different port 
* I think xmlhttp requests cross site also fail


In order to handle this in some cases people have implemented proxy servers that forward requests to other sites to get around cross origin restrictions.  This is a big extra overhead on developement.  I also suspect this may not work if we are packaging apps for even to host eventually.  If you keep this model, it means some basic webapps that could be hosted in app or by even are now always dependent on (potentially) smaller developer external webservers / proxy servers, which probably will end up creating stability issues (which people might associate with Even as a brand).

Example: I wrote a news reader, someone else wrote a reddit app - both required setting up a proxy / request forwarder as part of the web server that is serving the even app.

Easy fixes:
* Cross origin calls should be allowed (so far this includes fetch and xmlhttprequest)
* This is easy to do with flutter inappwebview (which you guys are using) - it involves:
  * adding some custom javascript that gets loaded and overrides fetch and xmlhttprequest to instead do a flutter call channel (similar to how the evenhub bridge works)
  * add flutter side call handlers to perform the actual operations, allowing cross site operations
  * Make sure some webView attributes are set in flutter (they may or may not be already):
    * allowFileAccessFromFileURLs true
    * allowUniversalAccessFromFileURLs true
    * mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW (allow me to fetch https from http or vice versa)

For an example of these fixes, I did this in my model of your guys app, it eased development of new apps drastically - see: 
* https://github.com/aegray/even_hub_emu/blob/main/lib/main.dart#L361 - add fetch javascript override
* https://github.com/aegray/even_hub_emu/blob/main/lib/main.dart#L398 - add xmlhttprequest javascript override
* https://github.com/aegray/even_hub_emu/blob/main/lib/main.dart#L610 - add flutter side handler for fetch








## EvenHub Oddities / quirks that could be improved:
* It's weird that scrolling in evenhub is the opposite direction of scrolling everywhere else in the firmware.  This just feels off as a user

* It would be nice if some more events are exposed - for example you don't get an event for scrolling a list but its sometimes useful to know what is currently highlighted.  I think (but may be wrong) that single click on a text doesn't work either (although looking at the bluetooth it is reported)
  

## Improvement: Audio transcription
I'm guessing you guys are already thinkign about this:
* Audio is great - if you guys could provide the same even ai transcription as an option that would be super useful so people don't have to implement their own.  Perhaps a bridge.audioTranscribeControl(true) and then an audioTranscribe event
  

## Improvement: image handling 
You are already communicating uncompressed bmp data for images over the ble connection - it would be very helpful if we could do the following:
* Send an explicit raw pixel buffer rather than png (or even bmp) data
* Allow partial updates to that raw pixel buffer - for example I might only want to update a small square of the full image, right now (as far as I can tell) I have to update the full image.
* (Not sure if this is possible depending on memory constraints) allow pre writing over images and then "switching" to a pre loaded buffer rather than having to write the data each time

## Improvement idea: Native functionality for free
This is not asking you to add native functionality - it's suggesting how you can allow it pretty easily with not a ton of work on your side:

There are a lot of places where you need some sort of native api for useful functionality - the way I've dealt with this is to build another app (generally flutter) that contains a small webserver and serves native requests to the even hub app.  
I've also been having this serve the actual even application too.  

One thing that would be very useful is if your even app had some sort of registration mechanism (maybe through android Intents, whatever is equivalent on iOS) to allow an external app to auto register an even hub application (rather than having to do it separately), 
so that if you install an app, it's auto available in evenHub.  

It would be very simple for the community to have a library that handled / setup most of this for people in other apps (rather than having to write a webserver).

This would also make it infinitely simpler to provide functionality that already exists in other apps.  If I already have an app that works, adding an even interface is way simpler than rewriting all app functionality into a (potentially more restrictive) setup.

I think this would also help you guys (Even) to solve a lot of requests for what is available in the api - instead of having to add xxxx feature to the api, almost everything is available on the native side.  

A good example is the request to be able to communicate with other ble devices - this really shouldn't be in the purview of your sdk, especially if you can auto allow for a bridge to native code.

If you (Even) are concerned that this takes some of the "appstore" aspect out of your guys control, it would be easy to have some sort of signing key or registration mechanism an app needs to go through to work with evenhub in this way - which would allow Even to control / own the appstore aspect still.

An example I've done this with:  I needed an interface to anki (flashcards) on phone - my native app provides both the evenhub webpage, proxy requests to get around cross origin restrictions, and translation of web requests into native anki api calls.


## Wishlist / Nice to haves but not critical
* not having an easy console in app for debugging (showing errors, logs etc) makes things a bit difficult especially when there is a delta between an emulator or simulator and the actual glasses.  It's possible to add in our code but just adds extra overhead.  It would be nice if there was some easy access to this in app or through the phone debug bridge

* If there was some access to the same llms even uses for even ai from apps that could be useful too (although I could understand if even didn't want to provide this)

* It's easy to crash even hub if you accidentally send too much image data or accidentally concurrently send - some of the api handling that for you would be good (I think you already rejected this though)

* Full unicode charset support - text updates are fast, someone was messing around with using unicode block characters to draw images instead of actual images, however it seemed that those characters weren't actually drawn on the glasses


