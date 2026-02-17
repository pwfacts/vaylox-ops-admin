class Unit {
  final String id;
  final String organizationId;
  final String name;
  final String code;
  final String? address;

  Unit({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.code,
    this.address,
  });

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'],
      organizationId: json['organization_id'],
      name: json['name'],
      code: json['code'],
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'name': name,
      'code': code,
      'address': address,
    };
  }
}
