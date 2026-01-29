import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/guard_model.dart';
import '../../data/repositories/guard_repository.dart';

class EnrollmentState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;

  EnrollmentState({this.isLoading = false, this.error, this.isSuccess = false});

  EnrollmentState copyWith({bool? isLoading, String? error, bool? isSuccess}) {
    return EnrollmentState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

class GuardEnrollmentNotifier extends StateNotifier<EnrollmentState> {
  final GuardRepository _repository;
  
  GuardEnrollmentNotifier(this._repository) : super(EnrollmentState());

  Future<void> enroll({
    required Guard guard,
    required Map<String, File> documents,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.enrollGuard(guard: guard, documents: documents);
      state = state.copyWith(isLoading: false, isSuccess: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final guardRepositoryProvider = Provider((ref) => GuardRepository());

final guardEnrollmentProvider = StateNotifierProvider<GuardEnrollmentNotifier, EnrollmentState>((ref) {
  return GuardEnrollmentNotifier(ref.watch(guardRepositoryProvider));
});
