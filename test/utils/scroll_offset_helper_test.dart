import 'package:PiliPlus/utils/scroll_offset_helper.dart';
import 'package:flutter_test/flutter_test.dart';

// The local cache list: rows of 112 in a list padded 7 at the top and
// 100 (plus the safe area) at the bottom.
const _extent = 112.0;
const _top = 7.0;
const _bottom = 100.0;
const _viewport = 600.0;
const _count = 10;

double _jump(int index) {
  final (double offset, double remain) = calcFixedItemOffset(
    index: index,
    itemCount: _count,
  );
  return adjustScrollOffset(
    offset: offset,
    remain: remain,
    viewportDimension: _viewport,
  );
}

void main() {
  const maxScroll = _top + _count * _extent + _bottom - _viewport;

  test('a row in the middle comes to the top, under the top padding', () {
    final scroll = _jump(3);
    expect(_top + 3 * _extent - scroll, _top);
  });

  test('the last row stays whole, above the bottom padding', () {
    final scroll = _jump(_count - 1);
    expect(scroll, lessThanOrEqualTo(maxScroll));
    final rowEnd = _top + _count * _extent - scroll;
    expect(rowEnd, lessThanOrEqualTo(_viewport - _bottom));
  });

  test('a row near the end jumps to where the list ends', () {
    expect(_jump(_count - 2), maxScroll);
  });
}
