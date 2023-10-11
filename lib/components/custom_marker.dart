import 'package:flutter/material.dart';

class MarkerIconWidget extends StatelessWidget {
  final GlobalKey _key;
  final String rate;

  MarkerIconWidget(this._key, this.rate);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _key,
      child: Container(
        padding: EdgeInsets.all(5.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              spreadRadius: 5,
              blurRadius: 7,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text('Rate: $rate'),
      ),
    );
  }
}
