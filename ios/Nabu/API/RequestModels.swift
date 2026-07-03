import Foundation

// MARK: - Auth

struct RegisterRequest: Codable {
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct MagicLinkRequest: Codable {
    let email: String
}

struct ForgotPasswordRequest: Codable {
    let email: String
}

struct ResetPasswordRequest: Codable {
    let token: String
    let password: String
}

struct ChangePasswordRequest: Codable {
    let currentPassword: String
    let newPassword: String
}

// MARK: - Household

struct CreateHouseholdRequest: Codable {
    let name: String
    let initials: String
}

struct UpdateHouseholdRequest: Codable {
    let name: String
    let initials: String
}

struct JoinHouseholdRequest: Codable {
    let inviteCode: String
}

struct UpdateMemberRoleRequest: Codable {
    let role: String
}

struct TransferOwnershipRequest: Codable {
    let newOwnerId: Int
}

// MARK: - Chores

struct CreateChoreRequest: Codable {
    let name: String
    let icon: String?
    let color: String?
    let category: String?
    let indicatorLabels: [String]?
    let indicatorDefaults: [String]?
    let followUpEnabled: Bool?
    let metricType: String?   // none | amount | rating | duration
    let metricUnit: String?   // unit label for amount metrics (mL/oz/g/min/custom)
    let subjects: [String]?

    init(name: String, icon: String?, color: String?, category: String?, indicatorLabels: [String]?, indicatorDefaults: [String]?, followUpEnabled: Bool?, metricType: String? = nil, metricUnit: String? = nil, subjects: [String]? = nil) {
        self.name = name
        self.icon = icon
        self.color = color
        self.category = category
        self.indicatorLabels = indicatorLabels
        self.indicatorDefaults = indicatorDefaults
        self.followUpEnabled = followUpEnabled
        self.metricType = metricType
        self.metricUnit = metricUnit
        self.subjects = subjects
    }

    enum CodingKeys: String, CodingKey {
        case name, icon, color, category
        case indicatorLabels, indicatorDefaults
        case followUpEnabled
        case metricType, metricUnit, subjects
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(indicatorLabels, forKey: .indicatorLabels)
        try container.encodeIfPresent(indicatorDefaults, forKey: .indicatorDefaults)
        try container.encodeIfPresent(followUpEnabled, forKey: .followUpEnabled)
        try container.encodeIfPresent(metricType, forKey: .metricType)
        try container.encodeIfPresent(metricUnit, forKey: .metricUnit)
        try container.encodeIfPresent(subjects, forKey: .subjects)
    }
}

struct ReorderChoresRequest: Codable {
    let choreIds: [Int]
}

// MARK: - Logs

struct CreateLogRequest: Codable {
    let choreId: Int
    let note: String?
    let indicators: [String]?
    let date: String?
    let hour: Int?
    let completedAt: String?
    let volumeML: Int?
    let userId: Int?
    let indicatorVolumes: [String: Int]?
    let followUpMinutes: Int?
    let followUpTime: String?
    let rating: Int?
    let durationSeconds: Int?
    let subject: String?
    /// Client-generated token (≤64 chars) so offline replays de-dup server-side.
    let idempotencyKey: String?

    init(choreId: Int, note: String?, indicators: [String]?, date: String?, hour: Int?, completedAt: String?, volumeML: Int?, userId: Int?, indicatorVolumes: [String: Int]?, followUpMinutes: Int?, followUpTime: String?, rating: Int? = nil, durationSeconds: Int? = nil, subject: String? = nil, idempotencyKey: String? = nil) {
        self.choreId = choreId
        self.note = note
        self.indicators = indicators
        self.date = date
        self.hour = hour
        self.completedAt = completedAt
        self.volumeML = volumeML
        self.userId = userId
        self.indicatorVolumes = indicatorVolumes
        self.followUpMinutes = followUpMinutes
        self.followUpTime = followUpTime
        self.rating = rating
        self.durationSeconds = durationSeconds
        self.subject = subject
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case choreId, note, indicators, date, hour, completedAt
        case volumeML = "volumeML"
        case userId
        case indicatorVolumes
        case followUpMinutes
        case followUpTime
        case rating, durationSeconds, subject, idempotencyKey
    }
}

struct UpdateLogRequest: Codable {
    let note: String?
    let indicators: [String]?
    let volumeML: Int?
    let userId: Int?
    let completedAt: String?
    let hour: Int?
    let date: String?
    let indicatorVolumes: [String: Int]?
    let rating: Int?
    let durationSeconds: Int?
    let subject: String?

    init(note: String?, indicators: [String]?, volumeML: Int?, userId: Int?, completedAt: String?, hour: Int?, date: String?, indicatorVolumes: [String: Int]?, rating: Int? = nil, durationSeconds: Int? = nil, subject: String? = nil) {
        self.note = note
        self.indicators = indicators
        self.volumeML = volumeML
        self.userId = userId
        self.completedAt = completedAt
        self.hour = hour
        self.date = date
        self.indicatorVolumes = indicatorVolumes
        self.rating = rating
        self.durationSeconds = durationSeconds
        self.subject = subject
    }

    enum CodingKeys: String, CodingKey {
        case note, indicators, date, hour, completedAt
        case volumeML = "volumeML"
        case userId
        case indicatorVolumes
        case rating, durationSeconds, subject
    }
}

// MARK: - Schedules

struct CreateScheduleRequest: Codable {
    let choreId: Int
    let frequencyType: String?
    let timePeriod: String?
    let specificTime: String?
    let daysOfWeek: [Int]?
    let intervalDays: Int?
    let dayOfMonth: Int?
    let monthWeekday: MonthWeekday?
    let monthOfYear: Int?
    let startDate: String?
    let recurrenceEnd: String?
    let targetCount: Int?
    let isActive: Bool?
    let assignedUserId: Int?
}

struct PatchScheduleRequest: Codable {
    let choreId: Int?
    let timePeriod: String?
    let specificTime: String??
    let frequencyType: String?
    let isActive: Bool?
    let daysOfWeek: [Int]?
    let intervalDays: Int?
    let dayOfMonth: Int?
    let monthOfYear: Int?
    let startDate: String??
    let recurrenceEnd: String??

    enum CodingKeys: String, CodingKey {
        case choreId, timePeriod, specificTime, frequencyType
        case isActive, daysOfWeek, intervalDays, dayOfMonth
        case monthOfYear, startDate, recurrenceEnd
    }
}

// MARK: - Preferences

struct PatchNotificationPrefsRequest: Codable {
    let pushEnabled: Bool?
    let emailEnabled: Bool?
    let enabledPushTypes: [String]?
    let defaultReminderLeadMinutes: Int?
}

struct PatchUserPreferencesRequest: Codable {
    var choreOrder: [Int]? = nil
    var hiddenHomeChoreIds: [Int]? = nil
    var timezone: String? = nil
    var volumeUnit: String? = nil
    var statsSectionOrder: [String]? = nil
    var statsSectionHidden: [String]? = nil
    var statsWidgets: [StatsWidget]? = nil
}

// MARK: - Push

struct PushSubscribeRequest: Codable {
    let subscription: PushSubscription
}

struct PushSubscription: Codable {
    let endpoint: String
    let keys: PushKeys
}

struct PushKeys: Codable {
    let p256dh: String
    let auth: String
}

struct PushUnsubscribeRequest: Codable {
    let endpoint: String
}

// MARK: - APNs

struct APNsRegisterRequest: Codable {
    let token: String
    let environment: String
    let bundleId: String
    let deviceName: String
}

struct APNsUnregisterRequest: Codable {
    let token: String
    let environment: String
}
