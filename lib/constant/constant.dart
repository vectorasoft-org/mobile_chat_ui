import 'package:flutter/material.dart';

extension HexColor on Color {
  /// String is in the format "aabbcc" or "ffaabbcc" with an optional leading "#".
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  /// Prefixes a hash sign if [leadingHashSign] is set to `true` (default is `true`).
  String toHex({bool leadingHashSign = true}) =>
      '${leadingHashSign ? '#' : ''}'
      '${((a * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0')}'
      '${((r * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0')}'
      '${((g * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0')}'
      '${((b * 255.0).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0')}';
}

// final mainColor = HexColor.fromHex('#054D9F');
final mainColor = HexColor.fromHex('#EC1D27');
final backgroudnColors = HexColor.fromHex('#F3F3F3');
final btnColor = HexColor.fromHex('#438287');
final secandaryBackgroud = HexColor.fromHex('#813F97');
final brownColor = HexColor.fromHex('#813F97');

//,color: Colors.black.withOpacity(0.8)
const textStyleNormal = TextStyle(fontFamily: 'Poppins', fontSize: 12);
const textStyleNormalBold = TextStyle(
  fontFamily: 'Poppins',
  fontSize: 24,
  fontWeight: FontWeight.bold,
);

const myFonntStyle = TextStyle(fontSize: 11);
const headerStyle = TextStyle(
  fontWeight: FontWeight.normal,
  fontSize: 16,
);

final headerStyleItem = TextStyle(
  fontWeight: FontWeight.normal,
  fontSize: 16,
  color: HexColor.fromHex('#808080'),
);
final myFonntStyleItem = TextStyle(
  fontSize: 12,
  color: Colors.black.withValues(alpha: 0.8),
);
final iconColors = HexColor.fromHex('#808080');

// alertLoading({required BuildContext context, String? title, Function}) {
//   FocusScope.of(context).unfocus();

//   showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (BuildContext context) {
//         return WillPopScope(
//           onWillPop: () async => false,
//           child: Center(
//             child: Container(
//               width: 80,
//               height: 80,
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: const BorderRadius.only(
//                     topLeft: Radius.circular(10),
//                     topRight: Radius.circular(10),
//                     bottomLeft: Radius.circular(10),
//                     bottomRight: Radius.circular(10)),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.grey.withOpacity(0.1),
//                     spreadRadius: 1,
//                     blurRadius: 1,
//                     offset: const Offset(0, 1), // changes position of shadow
//                   ),
//                 ],
//               ),
//               padding: const EdgeInsets.all(12),
//               child: const CircularProgressIndicator(),
//             ),
//           ),
//         );
//       });
// }

// void showAlertDialog(BuildContext context, {required String msg}) {
//   showDialog(
//       context: context,
//       builder: (BuildContext context) => CupertinoAlertDialog(
//             title: null,
//             content: Text(msg),
//             actions: <Widget>[
//               CupertinoDialogAction(
//                 onPressed: () {
//                   Navigator.pop(context);
//                 },
//                 isDefaultAction: true,
//                 child: Text("Close"),
//               ),
//               // CupertinoDialogAction(
//               //   child: Text("No"),
//               // )
//             ],
//           ));
// }

// void showAlertDialogClose(BuildContext context,
//     {required String msg, required Function() close}) {
//   showDialog(
//       context: context,
//       builder: (BuildContext context) => CupertinoAlertDialog(
//             title: null,
//             content: Text(msg),
//             actions: <Widget>[
//               CupertinoDialogAction(
//                 onPressed: close,
//                 isDefaultAction: true,
//                 child: Text("Close"),
//               ),
//               // CupertinoDialogAction(
//               //   child: Text("No"),
//               // )
//             ],
//           ));
// }

// Future<bool> isConnected() async {
//   var connectivityResult = await (Connectivity().checkConnectivity());
//   if (connectivityResult == ConnectivityResult.mobile) {
//     // I am connected to a mobile network.
//     return true;
//   } else if (connectivityResult == ConnectivityResult.wifi) {
//     // I am connected to a wifi network.
//     return true;
//   } else {
//     return false;
//   }
// }
