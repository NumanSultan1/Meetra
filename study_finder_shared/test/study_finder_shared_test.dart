import 'package:flutter_test/flutter_test.dart';
import 'package:study_finder_shared/study_finder_shared.dart';

void main() {
  test('UserModel maps serialization correctly', () {
    final user = UserModel(
      id: 'test_id',
      name: 'Test Student',
      email: 'test@uni.edu',
      university: 'Uni',
      semester: '1',
      subjects: ['Math'],
      profileImage: '',
      studyGoals: '',
      availability: '',
    );
    
    final map = user.toMap();
    expect(map['id'], 'test_id');
    expect(map['name'], 'Test Student');
  });
}
