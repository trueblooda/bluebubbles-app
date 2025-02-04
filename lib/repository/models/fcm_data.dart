import 'dart:async';

import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/repository/database.dart';
import 'package:bluebubbles/repository/models/config_entry.dart';
import 'package:firebase_dart/firebase_dart.dart';
import 'package:sqflite/sqflite.dart';

class FCMData {
  String? projectID;
  String? storageBucket;
  String? apiKey;
  String? firebaseURL;
  String? clientID;
  String? applicationID;

  FCMData({
    this.projectID,
    this.storageBucket,
    this.apiKey,
    this.firebaseURL,
    this.clientID,
    this.applicationID,
  });

  factory FCMData.fromMap(Map<String, dynamic> json) {
    Map<String, dynamic> projectInfo = json["project_info"];
    Map<String, dynamic> client = json["client"][0];
    String clientID = client["oauth_client"][0]["client_id"];
    return FCMData(
      projectID: projectInfo["project_id"],
      storageBucket: projectInfo["storage_bucket"],
      apiKey: client["api_key"][0]["current_key"],
      firebaseURL: projectInfo["firebase_url"],
      clientID: clientID.contains("-") ? clientID.substring(0, clientID.indexOf("-")) : clientID,
      applicationID: client["client_info"]["mobilesdk_app_id"],
    );
  }

  factory FCMData.fromConfigEntries(List<ConfigEntry> entries) {
    FCMData data = FCMData();
    for (ConfigEntry entry in entries) {
      if (entry.name == "projectID") {
        data.projectID = entry.value;
      } else if (entry.name == "storageBucket") {
        data.storageBucket = entry.value;
      } else if (entry.name == "apiKey") {
        data.apiKey = entry.value;
      } else if (entry.name == "firebaseURL") {
        data.firebaseURL = entry.value;
      } else if (entry.name == "clientID") {
        data.clientID = entry.value;
      } else if (entry.name == "applicationID") {
        data.applicationID = entry.value;
      }
    }
    return data;
  }

  Future<FCMData> save({Database? database}) async {
    List<ConfigEntry> entries = toEntries();
    for (ConfigEntry entry in entries) {
      await entry.save("fcm", database: database);
      prefs.setString(entry.name!, entry.value);
    }
    return this;
  }

  static void deleteFcmData() {
    prefs.remove('projectID');
    prefs.remove('storageBucket');
    prefs.remove('apiKey');
    prefs.remove('firebaseURL');
    prefs.remove('clientID');
    prefs.remove('applicationID');
  }

  static Future<void> initializeFirebase(FCMData data) async {
    var options = FirebaseOptions(
        appId: data.applicationID!,
        apiKey: data.apiKey!,
        projectId: data.projectID!,
        storageBucket: data.storageBucket,
        databaseURL: data.firebaseURL,
        messagingSenderId: data.clientID,
    );
    app = await Firebase.initializeApp(options: options);
  }

  static Future<FCMData> getFCM() async {
    Database? db = await DBProvider.db.database;

    List<Map<String, dynamic>> result = (await db?.query("fcm")) ?? [];
    if (result.isEmpty) {
      return FCMData(
        projectID: prefs.getString('projectID'),
        storageBucket: prefs.getString('storageBucket'),
        apiKey: prefs.getString('apiKey'),
        firebaseURL: prefs.getString('firebaseURL'),
        clientID: prefs.getString('clientID'),
        applicationID: prefs.getString('applicationID'),
      );
    }
    List<ConfigEntry> entries = [];
    for (Map<String, dynamic> setting in result) {
      entries.add(ConfigEntry.fromMap(setting));
    }
    return FCMData.fromConfigEntries(entries);
  }

  Map<String, dynamic> toMap() => {
        "project_id": projectID,
        "storage_bucket": storageBucket,
        "api_key": apiKey,
        "firebase_url": firebaseURL,
        "client_id": clientID,
        "application_id": applicationID,
      };

  List<ConfigEntry> toEntries() => [
        ConfigEntry(name: "projectID", value: projectID, type: projectID.runtimeType),
        ConfigEntry(name: "storageBucket", value: storageBucket, type: storageBucket.runtimeType),
        ConfigEntry(name: "apiKey", value: apiKey, type: apiKey.runtimeType),
        ConfigEntry(name: "firebaseURL", value: firebaseURL, type: firebaseURL.runtimeType),
        ConfigEntry(name: "clientID", value: clientID, type: clientID.runtimeType),
        ConfigEntry(name: "applicationID", value: applicationID, type: applicationID.runtimeType),
      ];
  bool get isNull =>
      projectID == null ||
      storageBucket == null ||
      apiKey == null ||
      firebaseURL == null ||
      clientID == null ||
      applicationID == null;
}
