/// Core shared models, schemas, and values for the StudyFinder platform.
library study_finder_shared;

import 'dart:convert';

/// Represents a student/user profile in the system.
class UserModel {
  final String id;
  final String name;
  final String email;
  final String university;
  final String semester;
  final List<String> subjects;
  final String profileImage;
  final String studyGoals;
  final String availability; // Represents schedule/availability (e.g. "Mon-Wed: 2pm-6pm")
  final bool? suspended;
  final List<String>? warnings;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.university,
    required this.semester,
    required this.subjects,
    required this.profileImage,
    required this.studyGoals,
    required this.availability,
    this.suspended,
    this.warnings,
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? university,
    String? semester,
    List<String>? subjects,
    String? profileImage,
    String? studyGoals,
    String? availability,
    bool? suspended,
    List<String>? warnings,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      university: university ?? this.university,
      semester: semester ?? this.semester,
      subjects: subjects ?? this.subjects,
      profileImage: profileImage ?? this.profileImage,
      studyGoals: studyGoals ?? this.studyGoals,
      availability: availability ?? this.availability,
      suspended: suspended ?? this.suspended,
      warnings: warnings ?? this.warnings,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'university': university,
      'semester': semester,
      'subjects': subjects,
      'profileImage': profileImage,
      'studyGoals': studyGoals,
      'availability': availability,
      if (suspended != null) 'suspended': suspended,
      if (warnings != null) 'warnings': warnings,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return UserModel(
      id: documentId,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      university: map['university'] ?? '',
      semester: map['semester'] ?? '',
      subjects: List<String>.from(map['subjects'] ?? []),
      profileImage: map['profileImage'] ?? '',
      studyGoals: map['studyGoals'] ?? '',
      availability: map['availability'] ?? '',
      suspended: map['suspended'] as bool?,
      warnings: map['warnings'] != null ? List<String>.from(map['warnings']) : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory UserModel.fromJson(String source, String documentId) =>
      UserModel.fromMap(json.decode(source), documentId);
}

/// Represents a study group.
class GroupModel {
  final String id;
  final String name;
  final String description;
  final String subject;
  final String semester;
  final String createdBy;
  final List<String> members; // List of user IDs
  final List<String> pendingMembers; // List of user IDs requesting to join

  GroupModel({
    required this.id,
    required this.name,
    required this.description,
    required this.subject,
    required this.semester,
    required this.createdBy,
    required this.members,
    this.pendingMembers = const [],
  });

  GroupModel copyWith({
    String? id,
    String? name,
    String? description,
    String? subject,
    String? semester,
    String? createdBy,
    List<String>? members,
    List<String>? pendingMembers,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      subject: subject ?? this.subject,
      semester: semester ?? this.semester,
      createdBy: createdBy ?? this.createdBy,
      members: members ?? this.members,
      pendingMembers: pendingMembers ?? this.pendingMembers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'subject': subject,
      'semester': semester,
      'createdBy': createdBy,
      'members': members,
      'pendingMembers': pendingMembers,
    };
  }

  factory GroupModel.fromMap(Map<String, dynamic> map, String documentId) {
    return GroupModel(
      id: documentId,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      subject: map['subject'] ?? '',
      semester: map['semester'] ?? '',
      createdBy: map['createdBy'] ?? '',
      members: List<String>.from(map['members'] ?? []),
      pendingMembers: List<String>.from(map['pendingMembers'] ?? []),
    );
  }

  String toJson() => json.encode(toMap());

  factory GroupModel.fromJson(String source, String documentId) =>
      GroupModel.fromMap(json.decode(source), documentId);
}

/// Represents a study session.
class SessionModel {
  final String id;
  final String title;
  final String subject;
  final DateTime date;
  final String createdBy;
  final List<String> participants; // List of user IDs

  SessionModel({
    required this.id,
    required this.title,
    required this.subject,
    required this.date,
    required this.createdBy,
    required this.participants,
  });

  SessionModel copyWith({
    String? id,
    String? title,
    String? subject,
    DateTime? date,
    String? createdBy,
    List<String>? participants,
  }) {
    return SessionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      date: date ?? this.date,
      createdBy: createdBy ?? this.createdBy,
      participants: participants ?? this.participants,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subject': subject,
      'date': date.toIso8601String(),
      'createdBy': createdBy,
      'participants': participants,
    };
  }

  factory SessionModel.fromMap(Map<String, dynamic> map, String documentId) {
    DateTime parsedDate;
    if (map['date'] != null) {
      try {
        parsedDate = DateTime.parse(map['date']);
      } catch (_) {
        parsedDate = DateTime.now();
      }
    } else {
      parsedDate = DateTime.now();
    }
    return SessionModel(
      id: documentId,
      title: map['title'] ?? '',
      subject: map['subject'] ?? '',
      date: parsedDate,
      createdBy: map['createdBy'] ?? '',
      participants: List<String>.from(map['participants'] ?? []),
    );
  }

  String toJson() => json.encode(toMap());

  factory SessionModel.fromJson(String source, String documentId) =>
      SessionModel.fromMap(json.decode(source), documentId);
}

/// Represents a chat message.
class MessageModel {
  final String id;
  final String senderId;
  final String receiverId; // Can be a user ID or group ID
  final String message;
  final DateTime timestamp;
  final List<String> deletedFor;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.deletedFor = const [],
  });

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? message,
    DateTime? timestamp,
    List<String>? deletedFor,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      deletedFor: deletedFor ?? this.deletedFor,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'deletedFor': deletedFor,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String documentId) {
    DateTime parsedTime;
    if (map['timestamp'] != null) {
      try {
        parsedTime = DateTime.parse(map['timestamp']);
      } catch (_) {
        parsedTime = DateTime.now();
      }
    } else {
      parsedTime = DateTime.now();
    }
    return MessageModel(
      id: documentId,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      message: map['message'] ?? '',
      timestamp: parsedTime,
      deletedFor: List<String>.from(map['deletedFor'] ?? []),
    );
  }

  String toJson() => json.encode(toMap());

  factory MessageModel.fromJson(String source, String documentId) =>
      MessageModel.fromMap(json.decode(source), documentId);
}

/// Represents shared academic notes.
class NoteModel {
  final String id;
  final String uploadedBy;   // Firebase UID
  final String uploaderName; // Display name stored at upload time
  final String title;
  final String fileUrl;
  final String subject;
  final String semester;
  final String teacher;
  final String groupId;
  final DateTime? uploadedAt;

  NoteModel({
    required this.id,
    required this.uploadedBy,
    this.uploaderName = '',
    required this.title,
    required this.fileUrl,
    required this.subject,
    required this.semester,
    required this.teacher,
    required this.groupId,
    this.uploadedAt,
  });

  NoteModel copyWith({
    String? id,
    String? uploadedBy,
    String? uploaderName,
    String? title,
    String? fileUrl,
    String? subject,
    String? semester,
    String? teacher,
    String? groupId,
    DateTime? uploadedAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploaderName: uploaderName ?? this.uploaderName,
      title: title ?? this.title,
      fileUrl: fileUrl ?? this.fileUrl,
      subject: subject ?? this.subject,
      semester: semester ?? this.semester,
      teacher: teacher ?? this.teacher,
      groupId: groupId ?? this.groupId,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uploadedBy': uploadedBy,
      'uploaderName': uploaderName,
      'title': title,
      'fileUrl': fileUrl,
      'subject': subject,
      'semester': semester,
      'teacher': teacher,
      'groupId': groupId,
      'uploadedAt': uploadedAt?.toIso8601String(),
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map, String documentId) {
    return NoteModel(
      id: documentId,
      uploadedBy: map['uploadedBy'] ?? '',
      uploaderName: map['uploaderName'] ?? '',
      title: map['title'] ?? '',
      fileUrl: map['fileUrl'] ?? '',
      subject: map['subject'] ?? '',
      semester: map['semester'] ?? '',
      teacher: map['teacher'] ?? '',
      groupId: map['groupId'] ?? '',
      uploadedAt: map['uploadedAt'] != null 
          ? DateTime.tryParse(map['uploadedAt']) 
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory NoteModel.fromJson(String source, String documentId) =>
      NoteModel.fromMap(json.decode(source), documentId);
}

/// Represents user moderation reports.
class ReportModel {
  final String id;
  final String reportedUser; // ID of the reported user
  final String? reportedUserName; // Name of the reported user
  final String reason;
  final String status; // 'pending', 'resolved'
  final String? evidenceUrl; // Screenshot or evidence URL
  final String? reportedBy; // ID of the reporter

  ReportModel({
    required this.id,
    required this.reportedUser,
    this.reportedUserName,
    required this.reason,
    required this.status,
    this.evidenceUrl,
    this.reportedBy,
  });

  ReportModel copyWith({
    String? id,
    String? reportedUser,
    String? reportedUserName,
    String? reason,
    String? status,
    String? evidenceUrl,
    String? reportedBy,
  }) {
    return ReportModel(
      id: id ?? this.id,
      reportedUser: reportedUser ?? this.reportedUser,
      reportedUserName: reportedUserName ?? this.reportedUserName,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      evidenceUrl: evidenceUrl ?? this.evidenceUrl,
      reportedBy: reportedBy ?? this.reportedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportedUser': reportedUser,
      if (reportedUserName != null) 'reportedUserName': reportedUserName,
      'reason': reason,
      'status': status,
      if (evidenceUrl != null) 'evidenceUrl': evidenceUrl,
      if (reportedBy != null) 'reportedBy': reportedBy,
    };
  }

  factory ReportModel.fromMap(Map<String, dynamic> map, String documentId) {
    return ReportModel(
      id: documentId,
      reportedUser: map['reportedUser'] ?? '',
      reportedUserName: map['reportedUserName'],
      reason: map['reason'] ?? '',
      status: map['status'] ?? 'pending',
      evidenceUrl: map['evidenceUrl'],
      reportedBy: map['reportedBy'],
    );
  }

  String toJson() => json.encode(toMap());

  factory ReportModel.fromJson(String source, String documentId) =>
      ReportModel.fromMap(json.decode(source), documentId);
}
