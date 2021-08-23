import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bluebubbles/blocs/chat_bloc.dart';
import 'package:bluebubbles/helpers/ui_helpers.dart';
import 'package:bluebubbles/helpers/utils.dart';
import 'package:bluebubbles/managers/method_channel_interface.dart';
import 'package:bluebubbles/managers/settings_manager.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class AvatarCrop extends StatefulWidget {
  final int index;
  AvatarCrop({required this.index});

  @override
  _AvatarCropState createState() => _AvatarCropState();
}

class _AvatarCropState extends State<AvatarCrop> {

  final _cropController = CropController();
  Uint8List? _imageData;
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).backgroundColor, // navigation bar color
        systemNavigationBarIconBrightness:
        Theme.of(context).backgroundColor.computeLuminance() > 0.5 ? Brightness.dark : Brightness.light,
        statusBarColor: Colors.transparent, // status bar color
      ),
      child: Scaffold(
          backgroundColor: Theme.of(context).backgroundColor,
          appBar: PreferredSize(
            preferredSize: Size(context.width, 80),
            child: ClipRRect(
              child: BackdropFilter(
                child: AppBar(
                  brightness: ThemeData.estimateBrightnessForColor(Theme.of(context).backgroundColor),
                  toolbarHeight: 100.0,
                  elevation: 0,
                  leading: buildBackButton(context),
                  backgroundColor: Theme.of(context).accentColor.withOpacity(0.5),
                  title: Text(
                    "Select & Crop Image",
                    style: Theme.of(context).textTheme.headline1,
                  ),
                  actions: [
                    AbsorbPointer(
                      absorbing: _imageData == null || _isLoading,
                      child: TextButton(
                          child: Text("SAVE",
                              style: Theme.of(context)
                                  .textTheme
                                  .subtitle1!
                                  .apply(color: _imageData == null || _isLoading ? Colors.grey : Theme.of(context).primaryColor)),
                          onPressed: () {
                            Get.defaultDialog(
                              title: "Saving avatar...",
                              titleStyle: Theme.of(context).textTheme.headline1,
                              confirm: Container(height: 0, width: 0),
                              cancel: Container(height: 0, width: 0),
                              content: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    SizedBox(
                                      height: 15.0,
                                    ),
                                    buildProgressIndicator(context),
                                  ]
                              ),
                              barrierDismissible: false,
                              backgroundColor: Theme.of(context).backgroundColor,
                            );
                            _cropController.crop();
                          }),
                    ),
                  ],
                ),
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              ),
            ),
          ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              children: [
                if (_imageData != null)
                  Container(
                    height: context.height / 2,
                    child: Crop(
                        controller: _cropController,
                        image: _imageData!,
                        onCropped: (croppedData) async {
                          String appDocPath = SettingsManager().appDocDir.path;
                          File file = new File(ChatBloc().chats[widget.index].customAvatarPath.value ?? "$appDocPath/avatars/${ChatBloc().chats[widget.index].guid!.characters.where((char) => char.isAlphabetOnly).join()}/avatar.jpg");
                          if (ChatBloc().chats[widget.index].customAvatarPath.value == null) {
                            await file.create(recursive: true);
                          }
                          await file.writeAsBytes(croppedData);
                          ChatBloc().chats[widget.index].customAvatarPath.trigger(file.path);
                          ChatBloc().chats[widget.index].save();
                          Get.back(closeOverlays: true);
                          showSnackbar("Notice", "Custom chat avatar saved successfully");
                        },
                        onStatusChanged: (status) {
                          if (status == CropStatus.ready || status == CropStatus.cropping) {
                            setState(() {
                              _isLoading = false;
                            });
                          } else {
                            setState(() {
                              _isLoading = true;
                            });
                          }
                        },
                        withCircleUi: true,
                        initialSize: 0.5,
                      ),
                  ),
                if (_imageData == null)
                  Container(
                    height: context.height / 2,
                    child: Center(
                      child: Text("Pick an image to crop it for a custom avatar"),
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    primary: Theme.of(context).primaryColor,
                  ),
                  onPressed: () async {
                    List<dynamic>? res = await MethodChannelInterface().invokeMethod("pick-file", {
                      "mimeTypes": ["image/*"],
                      "allowMultiple": false,
                    });
                    if (res == null || res.isEmpty) return;

                    setState(() {
                      _imageData = File(res.first.toString()).readAsBytesSync();
                    });
                  },
                  child: Text(
                    "Pick Image",
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyText1!.color,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
      ),
    );
  }
}