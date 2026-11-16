import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
part 'database.g.dart';
// FIXED v1.0.1: all ids use clientDefault (Uuid().v4() is NOT const, Constant() would fail).
// Added Lines.creditPiasters for explicit overpayment / advance credit.
class Customers extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get whatsapp => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get registeredAt => dateTime().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
class Packages extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text().unique()();
  IntColumn get pricePiasters => integer()();
  TextColumn get description => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
class PackagePriceHistory extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get packageId => text().references(Packages, #id)();
  IntColumn get oldPricePiasters => integer()();
  IntColumn get newPricePiasters => integer()();
  IntColumn get effectiveYear => integer()();
  IntColumn get effectiveMonth => integer()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  @override Set<Column> get primaryKey => {id};
}
class Lines extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get packageId => text().references(Packages, #id)();
  TextColumn get number => text().unique()();
  TextColumn get carrier => text().withDefault(const Constant('Orange'))();
  TextColumn get lineType => text().withDefault(const Constant('calls'))();
  TextColumn get ownerName => text().nullable()();
  IntColumn get startYear => integer().nullable()();
  IntColumn get startMonth => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get notes => text().nullable()();
  IntColumn get creditPiasters => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get stoppedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
class BillingCycles extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get lineId => text().references(Lines, #id)();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get pricePiasters => integer()();
  TextColumn get packageNameSnapshot => text()();
  IntColumn get paidPiasters => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('unpaid'))();
  @override Set<Column> get primaryKey => {id};
  @override List<Set<Column>> get uniqueKeys => [{lineId, year, month}];
}
class Payments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get lineId => text().references(Lines, #id)();
  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get amountPiasters => integer()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get reference => text().nullable()();
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get collectorName => text().withDefault(const Constant('ماما'))();
  TextColumn get receiptNumber => text().unique()();
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  @override Set<Column> get primaryKey => {id};
}
class PaymentAllocations extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get paymentId => text().references(Payments, #id)();
  TextColumn get billingCycleId => text().references(BillingCycles, #id)();
  IntColumn get amountPiasters => integer()();
  @override Set<Column> get primaryKey => {id};
}
class Expenses extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get title => text()();
  IntColumn get amountPiasters => integer()();
  DateTimeColumn get spentAt => dateTime()();
  TextColumn get category => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  @override Set<Column> get primaryKey => {id};
}
class Notifications extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get lineId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  BoolColumn get isSent => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {id};
}
class AuditLogs extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  @override Set<Column> get primaryKey => {id};
}
class SyncQueue extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  @override Set<Column> get primaryKey => {id};
}
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override Set<Column> get primaryKey => {key};
}
@DriftDatabase(tables: [Customers, Packages, PackagePriceHistory, Lines, BillingCycles, Payments, PaymentAllocations, Expenses, Notifications, AuditLogs, SyncQueue, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'line_manager.db'));
  @override int get schemaVersion => 4;
  @override MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => await m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) { await m.addColumn(lines, lines.stoppedAt); }
      if (from < 3) { await m.addColumn(lines, lines.creditPiasters); }
      if (from < 4) { await m.addColumn(payments, payments.idempotencyKey); }
    },
    beforeOpen: (details) async {
      await customStatement('CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_lines_number ON lines(number)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_lines_customer ON lines(customer_id)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_cycles_line ON billing_cycles(line_id, year, month)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_payments_line ON payments(line_id, paid_at)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_payments_receipt ON payments(receipt_number)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id)');
      await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_idempotency ON payments(idempotency_key) WHERE idempotency_key IS NOT NULL');
    },
  );
  Future<void> audit(String type, String? eid, String action, {String? oldV, String? newV}) async {
    final id = const Uuid().v4();
    await into(auditLogs).insert(AuditLogsCompanion.insert(
      id: Value(id),
      entityType: type,
      entityId: Value(eid),
      action: action,
      oldValue: Value(oldV),
      newValue: Value(newV),
    ));
    await enqueueSync('audit', id, 'upsert', '{}');
  }
  Future<void> enqueueSync(String type, String eid, String op, String json) async {
    await into(syncQueue).insert(
  SyncQueueCompanion.insert(
    id: Value(const Uuid().v4()),
    entityType: type,
    entityId: eid,
    operation: op,
    payloadJson: json,
  ),
);
  }
}
