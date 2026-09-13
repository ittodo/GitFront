import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/l10n.dart';

void main() {
  test('submodule and subtree strings support Korean and English', () {
    final korean = GitFrontStrings(const Locale('ko'));
    final english = GitFrontStrings(const Locale('en'));

    expect(korean.submodules, '서브모듈');
    expect(english.submodules, 'Submodules');
    expect(korean.addSubmodule, '서브모듈 추가');
    expect(english.addSubmodule, 'Add submodule');
    expect(korean.registerExistingSubtree, '기존 Subtree 등록');
    expect(english.registerExistingSubtree, 'Register existing subtree');
    expect(korean.subtreeSquash, '이력을 하나의 커밋으로 합치기');
    expect(english.subtreeSquash, 'Squash history');
    expect(
      korean.removeSubmoduleOperation('vendor/lib'),
      '서브모듈 제거: vendor/lib',
    );
    expect(
      english.removeSubmoduleOperation('vendor/lib'),
      'Remove submodule: vendor/lib',
    );
  });

  test('common workspace controls support Korean and English', () {
    final korean = GitFrontStrings(const Locale('ko'));
    final english = GitFrontStrings(const Locale('en'));

    expect(korean.settings, '설정');
    expect(english.settings, 'Settings');
    expect(korean.noCommits, '커밋이 없습니다');
    expect(english.noCommits, 'No commits');
    expect(korean.discardChangesQuestion, '변경을 폐기할까요?');
    expect(english.discardChangesQuestion, 'Discard changes?');
    expect(korean.fetch, 'Fetch');
    expect(english.fetch, 'Fetch');
  });
}
