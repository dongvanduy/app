import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../domain/entities/code_entity.dart';
import '../../domain/entities/search_list_entity.dart';
import '../../domain/usecases/manage_codes_usecase.dart';

class CodeProvider with ChangeNotifier {
  final ManageCodesUseCase useCase;
  final Connectivity connectivity;

  List<SearchListEntity> _searchLists = [];
  List<CodeEntity> _codeList = [];
  List<String> _foundCodes = [];
  List<String> _orderedFoundCodes = [];
  List<String> _recentlyScannedCodes = [];
  bool _isLoading = false;
  String? _error;

  int _selectedIndex = 0;
  int? _selectedSearchListIndex;

  String? _scannedSerialNumber;
  String? _retestResult;
  File? _retestImage;
  bool _isSubmittingRetest = false;
  String? _retestError;
  String _employeeId = 'debug';
  String? _notes;
  String _handOverStatus = 'WAITING_HAND_OVER';

  List<SearchListEntity> get searchLists => _searchLists;
  List<CodeEntity> get codeList => _codeList;
  List<String> get foundCodes => _foundCodes;
  List<String> get recentlyScannedCodes => _recentlyScannedCodes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get selectedIndex => _selectedIndex;
  int? get selectedSearchListIndex => _selectedSearchListIndex;

  int get foundCount => _foundCodes.length;
  int get totalCount => _codeList.length;

  String? get scannedSerialNumber => _scannedSerialNumber;
  String? get retestResult => _retestResult;
  File? get retestImage => _retestImage;
  bool get isSubmittingRetest => _isSubmittingRetest;
  String? get retestError => _retestError;
  String get employeeId => _employeeId;
  String? get notes => _notes;
  String get handOverStatus => _handOverStatus;

  CodeProvider({
    required this.useCase,
    required this.connectivity,
  });

  Future<bool> _isConnected() async {
    final result = await connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  void resetSessionState() {
    _selectedIndex = 0;
    _searchLists = [];
    _codeList = [];
    _foundCodes = [];
    _orderedFoundCodes = [];
    _recentlyScannedCodes = [];
    _selectedSearchListIndex = null;
    notifyListeners();
  }

  Future<void> fetchSearchList() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    if (!await _isConnected()) {
      _error = 'Không có kết nối mạng';
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      _searchLists = await useCase.getSearchList();
    } catch (e) {
      _error = e.toString();
    }
    _selectedSearchListIndex = null;
    _recentlyScannedCodes = [];
    _updateCodeList();
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> handleScanCode(String rawCode) async {
    if (_selectedSearchListIndex == null) {
      _error = 'Vui lòng chọn một danh sách trước khi quét!';
      notifyListeners();
      return false;
    }

    final serialNumber = rawCode.trim();
    if (serialNumber.isEmpty) {
      _error = 'Serial Number không được để trống.';
      notifyListeners();
      return false;
    }

    final codeExists = _codeList.any(
      (item) => item.serialNumber == serialNumber,
    );
    if (!codeExists) {
      _error = 'SN $serialNumber không nằm trong danh sách đã chọn.';
      notifyListeners();
      return false;
    }

    if (_foundCodes.contains(serialNumber)) {
      _promoteFoundCode(serialNumber);
      _error = null;
      notifyListeners();
      return true;
    }

    try {
      await useCase.scanSerialNumber(serialNumber);
      _promoteFoundCode(serialNumber);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void _promoteFoundCode(String serialNumber) {
    if (!_foundCodes.contains(serialNumber)) {
      _foundCodes.add(serialNumber);
    }

    _orderedFoundCodes.remove(serialNumber);
    _recentlyScannedCodes.remove(serialNumber);
    _orderedFoundCodes.insert(0, serialNumber);
    _recentlyScannedCodes.insert(0, serialNumber);

    final scannedCode = _codeList.firstWhere(
      (item) => item.serialNumber == serialNumber,
    );
    _codeList = [
      scannedCode.copyWith(isFound: true, foundOrder: 1),
      ..._codeList
          .where((item) => item.serialNumber != serialNumber)
          .map((item) {
        if (item.isFound && _orderedFoundCodes.contains(item.serialNumber)) {
          return item.copyWith(
            foundOrder: _orderedFoundCodes.indexOf(item.serialNumber) + 1,
          );
        }
        return item;
      }),
    ];

    final selectedIndex = _selectedSearchListIndex!;
    _searchLists = [
      for (var index = 0; index < _searchLists.length; index++)
        index == selectedIndex
            ? _searchLists[index].copyWith(items: List.of(_codeList))
            : _searchLists[index],
    ];
  }

  void setSelectedIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void setSelectedSearchListIndex(int index) {
    _selectedSearchListIndex = index;
    _recentlyScannedCodes = [];
    print('Selected search list index: $index');
    _updateCodeList();
  }

  void _updateCodeList() {
    if (_selectedSearchListIndex != null && _searchLists.isNotEmpty) {
      _codeList = _searchLists[_selectedSearchListIndex!].items;
      _foundCodes = _codeList
          .where((item) => item.isFound)
          .map((item) => item.serialNumber)
          .toList();
      print('Updated _codeList: $_codeList');
      print('Updated _foundCodes: $_foundCodes');

      _orderedFoundCodes = _foundCodes.toList();
      _codeList = _codeList.map((item) {
        if (_orderedFoundCodes.contains(item.serialNumber)) {
          return item.copyWith(
              foundOrder: _orderedFoundCodes.indexOf(item.serialNumber) + 1);
        }
        return item;
      }).toList();
    } else {
      _codeList = [];
      _foundCodes = [];
      _orderedFoundCodes = [];
      _recentlyScannedCodes = [];
      print('Cleared _codeList: $_codeList');
    }
    notifyListeners();
  }

  // Thêm phương thức updateScannedSerialNumber

  //===========CHUC NANG RETEST=============

  void updateScannedSerialNumber(String serialNumber) {
    _scannedSerialNumber = serialNumber;
    _retestResult = null;
    _retestImage = null;
    _retestError = null;
    notifyListeners();
  }

  // Chọn trạng thái Pass/Fail
  void setRetestResult(String? result) {
    _retestResult = result;
    notifyListeners();
  }

  // Nhập ghi chú
  void setNotes(String? notes) {
    _notes = notes;
    notifyListeners();
  }

  // Chụp ảnh
  Future<void> pickImage() async {
    try {
      await _requestCameraPermission();
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);

      if (pickedFile != null) {
        _retestImage = File(pickedFile.path);
        notifyListeners();
      }
    } catch (e) {
      _retestError = 'Lỗi khi chụp ảnh: $e';
      notifyListeners();
    }
  }

  // Gửi kết quả Retest lên API
  Future<void> submitRetest() async {
    if (_scannedSerialNumber == null ||
        _retestResult == null ||
        _retestImage == null) {
      print(
          'Validation failed: serialNumber=$_scannedSerialNumber, result=$_retestResult, image=$_retestImage');
      _retestError = 'Vui lòng điền đầy đủ thông tin (mã, trạng thái, và ảnh).';
      notifyListeners();
      return;
    }
    // // Kiểm tra status
    // if (_retestResult != 'Pass' && _retestResult != 'Fail') {
    //   print('Invalid status: $_retestResult');
    //   _retestError = 'Trạng thái chỉ được là "Pass" hoặc "Fail".';
    //   notifyListeners();
    //   return;
    // }

    // Kiểm tra file ảnh
    if (!await _retestImage!.exists()) {
      print('Image file does not exist: ${_retestImage!.path}');
      _retestError = 'File ảnh không tồn tại.';
      notifyListeners();
      return;
    }

    _isSubmittingRetest = true;
    _retestError = null;
    notifyListeners();
    print('Starting submission process...');

    try {
      print(
          'Sending: serialNumber=$_scannedSerialNumber, status=$_retestResult, employeeId=$_employeeId, notes=$_notes, handOverStatus=$_handOverStatus, imagePath=${_retestImage!.path}');
      final client = _createIoClient();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
            'https://pembd-adapter.cns.myfiinet.com/api/RetestResult/submit-with-img'),
      );

      request.fields['serialNumber'] = _scannedSerialNumber!;
      request.fields['status'] = _retestResult!;
      request.fields['employeeId'] = _employeeId;
      request.fields['notes'] = _notes ?? '';
      request.fields['handOverStatus'] = _handOverStatus;
      request.files
          .add(await http.MultipartFile.fromPath('image', _retestImage!.path));

      var response =
          await client.send(request).timeout(const Duration(seconds: 60));

      print('API response status: ${response.statusCode}');
      var responseBody = await http.Response.fromStream(response);
      print('API response body: ${responseBody.body}');

      if (response.statusCode == 200) {
        print('Submission successful');
        _scannedSerialNumber = null;
        _retestResult = null;
        _retestImage = null;
        _notes = null;
        _retestError = null;
      } else {
        print('Submission failed with status: ${response.statusCode}');
        _retestError =
            'Lỗi khi gửi kết quả: ${response.statusCode} - ${responseBody.body}';
      }
    } catch (e) {
      print('Error in submitRetest: $e');
      _retestError = 'Lỗi khi gửi kết quả: $e';
    }

    _isSubmittingRetest = false;
    notifyListeners();
    print('submitRetest completed');
  }

  // Lấy kết quả Retest từ API
  Future<Map<String, dynamic>> fetchRetestResult(String serialNumber) async {
    try {
      final client = _createIoClient();
      final response = await client.get(
        Uri.parse(
            'https://pembd-adapter.cns.myfiinet.com/api/RetestResult/get-result/$serialNumber'),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.body};
      } else {
        return {
          'success': false,
          'error':
              'Failed to fetch result: ${response.statusCode} - ${response.body}'
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Thêm phương thức requestCameraPermission (public)
  Future<void> requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (!status.isGranted) {
      throw Exception('Camera permission denied');
    }
  }

  // Phương thức private để gọi trong các hàm khác
  Future<void> _requestCameraPermission() async {
    await requestCameraPermission();
  }

  http.Client _createIoClient() {
    return http.Client();
  }
}
