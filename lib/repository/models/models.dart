export 'package:bluebubbles/repository/models/io/attachment.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/attachment.dart';

export 'package:bluebubbles/repository/models/io/chat.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/chat.dart';

export 'package:bluebubbles/repository/models/io/fcm_data.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/fcm_data.dart';

export 'package:bluebubbles/repository/models/io/handle.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/handle.dart';

export 'package:bluebubbles/repository/models/io/join_tables.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/join_tables.dart';

export 'package:bluebubbles/repository/models/io/js.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/js.dart';

export 'package:bluebubbles/repository/models/io/message.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/message.dart';

export 'package:bluebubbles/repository/models/io/scheduled.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/scheduled.dart';

export 'package:bluebubbles/repository/models/io/theme_entry.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/theme_entry.dart';

export 'package:bluebubbles/repository/models/io/theme_object.dart'
if (dart.library.html) 'package:bluebubbles/repository/models/html/theme_object.dart';

export 'package:bluebubbles/repository/models/platform_file.dart';

import 'dart:typed_data';

import 'package:fast_contacts/fast_contacts.dart';

class Contact {
  Contact({
    required this.id,
    required this.displayName,
    this.phones = const [],
    this.emails = const [],
    this.structuredName,
    this.avatar,
  });

  String id;
  String displayName;
  List<String> phones;
  List<String> emails;
  StructuredName? structuredName;
  Uint8List? avatar;

  Map<String, dynamic> toMap() {
    return {
      'id': this.id,
      'displayName': this.displayName,
      'phones': this.phones,
      'emails': this.emails,
    };
  }

  factory Contact.fromMap(Map<String, dynamic> map) {
    // backwards compatibility with old contacts plugin
    if (map['phones'].isNotEmpty && map['phones'][0] is Map<String, dynamic>) {
      map['phones'] = map['phones'].map((e) => e['value'] ?? "").toList();
    }
    if (map['emails'].isNotEmpty && map['emails'][0] is Map<String, dynamic>) {
      map['emails'] = map['emails'].map((e) => e['value'] ?? "").toList();
    }
    return Contact(
      id: (map['id'] ?? map['identifier']) as String,
      displayName: map['displayName'] as String,
      phones: map['phones'].cast<String>(),
      emails: map['emails'].cast<String>(),
    );
  }
}