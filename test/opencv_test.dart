import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

void main() {
  test('Mat methods and submat', () {
    final mat = cv.Mat.zeros(100, 100, cv.MatType.CV_8UC1);
    final sub = mat.region(cv.Rect(20, 20, 60, 60));
    expect(sub.rows, 60);
    expect(sub.cols, 60);

    final data = mat.data;
    expect(data.length, 10000);

    mat.dispose();
    sub.dispose();
  });
}
