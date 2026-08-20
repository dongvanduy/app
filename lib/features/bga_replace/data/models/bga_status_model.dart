class BgaStatusModel {
  final String sn;
  final String? taskNumber;
  final String? internalTask;
  final String? desc;
  final int? applyTaskStatus;
  final String? statusName;
  final String? findBoardStatus;
  final String? approveScrapperson;
  final DateTime? applyTime;
  final DateTime? createTime;
  final String? category;
  final String? remark;
  final bool isValid;
  final String? message;
  final String? source;

  BgaStatusModel({
    required this.sn,
    this.taskNumber,
    this.internalTask,
    this.desc,
    this.applyTaskStatus,
    this.statusName,
    this.findBoardStatus,
    this.approveScrapperson,
    this.applyTime,
    this.createTime,
    this.category,
    this.remark,
    required this.isValid,
    this.message,
    this.source,
  });

  factory BgaStatusModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? value) {
      if (value == null || value.isEmpty) return null;
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }

    return BgaStatusModel(
      sn: json['sn']?.toString() ?? '',
      taskNumber: json['taskNumber']?.toString(),
      internalTask: json['internalTask']?.toString(),
      desc: json['desc']?.toString(),
      applyTaskStatus: json['applyTaskStatus'] as int?,
      statusName: json['statusName']?.toString(),
      findBoardStatus: json['findBoardStatus']?.toString(),
      approveScrapperson: json['approveScrapperson']?.toString(),
      applyTime: parseDate(json['applyTime']?.toString()),
      createTime: parseDate(json['createTime']?.toString()),
      category: json['category']?.toString(),
      remark: json['remark']?.toString(),
      isValid: json['isValid'] == true,
      message: json['message']?.toString(),
      source: json['source']?.toString(),
    );
  }

  BgaStatusModel copyWith({
    int? applyTaskStatus,
    String? remark,
    bool? isValid,
    String? message,
  }) {
    return BgaStatusModel(
      sn: sn,
      taskNumber: taskNumber,
      internalTask: internalTask,
      desc: desc,
      applyTaskStatus: applyTaskStatus ?? this.applyTaskStatus,
      statusName: statusName,
      findBoardStatus: findBoardStatus,
      approveScrapperson: approveScrapperson,
      applyTime: applyTime,
      createTime: createTime,
      category: category,
      remark: remark ?? this.remark,
      isValid: isValid ?? this.isValid,
      message: message ?? this.message,
      source: source,
    );
  }

  String get statusLabel {
    if (applyTaskStatus == 10) {
      return 'Chờ Check In Barking';
    }
    if (applyTaskStatus == 11) {
      return 'Chờ Check Out Barking';
    }
    if (applyTaskStatus != null) {
      return 'Không hỗ trợ cập nhật';
    }
    return 'Không có dữ liệu';
  }

  bool get canUpdate => applyTaskStatus == 10 || applyTaskStatus == 11;
}
