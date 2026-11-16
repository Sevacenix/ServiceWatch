import Foundation

enum PriceEvent: String, CaseIterable, Identifiable, Sendable {
    case june = "618"
    case november = "双 11"
    case blackFriday = "黑五"
    var id: Self { self }

    func window(year: Int) -> Range<Date> {
        let calendar = PriceCalendar.calendar
        switch self {
        case .june: return PriceCalendar.date(year, 6, 1)..<PriceCalendar.date(year, 6, 19)
        case .november: return PriceCalendar.date(year, 11, 1)..<PriceCalendar.date(year, 11, 12)
        case .blackFriday:
            let first = PriceCalendar.date(year, 11, 1)
            let firstThursday = (5 - calendar.component(.weekday, from: first) + 7) % 7
            let friday = PriceCalendar.date(year, 11, firstThursday + 23)
            return friday..<calendar.date(byAdding: .day, value: 3, to: friday)!
        }
    }
}

enum PriceCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: .init(year: year, month: month, day: day))!
    }
    static func year(_ date: Date) -> Int { calendar.component(.year, from: date) }
    static func yearWindow(_ year: Int) -> Range<Date> { date(year, 1, 1)..<date(year + 1, 1, 1) }
    static func label(_ window: Range<Date>) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: window.upperBound)!
        return "\(ServiceDate.string(window.lowerBound)) 至 \(ServiceDate.string(last))"
    }
}

struct PricePoint: Sendable, Equatable {
    let amount: Decimal
    let observedAt: Date

    init?(price: String?, at date: Date) {
        guard let price, RenewalPlan.validAmount(price),
              let amount = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN
        else { return nil }
        self.amount = amount
        observedAt = date
    }

    var label: String { NSDecimalNumber(decimal: amount).stringValue }
}

struct PriceLow: Sendable {
    private(set) var point: PricePoint?
    private var days: Set<Date> = []
    var sampledDays: Int { days.count }
    mutating func observe(_ sample: PricePoint) {
        days.insert(PriceCalendar.calendar.startOfDay(for: sample.observedAt))
        if let point, (point.amount, point.observedAt) <= (sample.amount, sample.observedAt) { return }
        point = sample
    }
}

struct PriceYear: Sendable {
    var low = PriceLow()
    var events: [PriceEvent: PriceLow] = [:]
}

struct PriceComparison: Sendable {
    var historical = PriceLow()
    var years: [Int: PriceYear] = [:]
    var firstSample: Date?
    var chart: [OfferObservation] = []

    mutating func observe(_ sample: PricePoint) {
        historical.observe(sample)
        firstSample = min(firstSample ?? sample.observedAt, sample.observedAt)
        let year = PriceCalendar.year(sample.observedAt)
        years[year, default: PriceYear()].low.observe(sample)
        for event in PriceEvent.allCases where event.window(year: year).contains(sample.observedAt) {
            years[year, default: PriceYear()].events[event, default: PriceLow()].observe(sample)
        }
    }
}

struct PriceDelta: Equatable {
    let amount: Decimal
    let fraction: Decimal?
    init(current: PricePoint, reference: PricePoint) {
        amount = current.amount - reference.amount
        fraction = reference.amount > 0 ? amount / reference.amount : nil
    }
    var description: String {
        if amount == 0 { return "持平" }
        let sign = amount > 0 ? "+" : "−"
        let absolute = amount > 0 ? amount : -amount
        let difference = sign + NSDecimalNumber(decimal: absolute).stringValue
        guard let fraction else { return difference }
        let percent = (fraction > 0 ? fraction : -fraction).formatted(.percent.precision(.fractionLength(0...1)))
        return "\(difference)（\(sign)\(percent)）"
    }
}
