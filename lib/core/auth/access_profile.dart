class AccessProfile {
  final String userId;
  final String? email;
  final String? organizationId;
  final String role;
  final bool isPlatformAdmin;

  AccessProfile({
    required this.userId,
    this.email,
    this.organizationId,
    required this.role,
    required this.isPlatformAdmin,
  });

  @override
  String toString() {
    return 'AccessProfile(userId: $userId, role: $role, isPlatformAdmin: $isPlatformAdmin, organizationId: $organizationId)';
  }
}
