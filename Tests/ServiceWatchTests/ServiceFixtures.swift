@testable import ServiceWatch

enum ServiceFixtures {
    static let services: [Service] = [
        .init(id: 1, name: "示例画布", category: "软件授权", symbol: "paintbrush", tint: .teal, paid: true,
              entitlements: [.init(tier: "买断版", expires: nil, perpetual: true)], offerPath: nil),
        .init(id: 2, name: "示例影院", category: "视频", symbol: "play.tv", tint: .pink, paid: true,
              entitlements: [.init(tier: "超级大会员", expires: "2031-02-20"),
                             .init(tier: "大会员", expires: "2032-11-12")],
              channel: "App Store", method: "苹果支付", autoRenew: "待核实", nextCharge: "2031-02-14",
              nextAmount: "159", offerPath: nil, billingCycle: "连续包年"),
        .init(id: 3, name: "示例视频", category: "视频", symbol: "play.rectangle", tint: .orange, paid: true,
              entitlements: [.init(tier: "SVIP", expires: "2031-09-14"), .init(tier: "VIP", expires: "2032-10-02")], offerPath: nil),
        .init(id: 5, name: "示例音频", category: "音乐", symbol: "music.note", tint: .green, paid: true,
              entitlements: [.init(tier: "音乐", expires: "2031-10-04"), .init(tier: "高清", expires: "2032-02-17"),
                             .init(tier: "有声书", expires: "2031-11-03")], offerPath: nil),
        .init(id: 12, name: "示例办公", category: "办公", symbol: "doc", tint: .blue, paid: true,
              entitlements: [.init(tier: "专业版", expires: "2090-03-18")], offerPath: nil)
    ]

    static func seed(_ repository: AuthorizationRepository) throws {
        try repository.save(AuthorizationArchive(services: services).migrated())
    }
}
