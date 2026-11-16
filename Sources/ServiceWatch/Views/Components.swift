import SwiftUI

struct ServiceIcon: View {
    var service: Service
    var catalog: CatalogStore
    var size: CGFloat = 32
    var body: some View {
        BrandIconView(sources: catalog.iconSources(for: service), customIcon: service.customIcon, store: catalog.icons, size: size)
    }
}

struct BrandIconView: View {
    var sources: [String]
    var customIcon: String? = nil
    @Bindable var store: BrandIconStore
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            if let custom = store.customImage(customIcon) { logo(custom, side: size) }
            else if sources.count > 1 {
                ForEach(Array(sources.prefix(2).enumerated()), id: \.offset) { index, source in
                    Group {
                        if let image = store.image(source) { logo(image, side: size * 0.72) }
                        else { placeholder(side: size * 0.72) }
                    }.offset(x: size * (index == 0 ? -0.12 : 0.12), y: size * (index == 0 ? -0.12 : 0.12))
                }
            } else if let source = sources.first, let image = store.image(source) { logo(image, side: size) }
            else { placeholder(side: size) }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .task(id: sources.joined(separator: "|")) {
                for source in sources { await store.load(source) }
            }
    }
    private func logo(_ image: NSImage, side: CGFloat) -> some View {
        Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.2))
            .overlay(RoundedRectangle(cornerRadius: side * 0.2).stroke(.quaternary, lineWidth: 0.5))
    }
    private func placeholder(side: CGFloat) -> some View {
        Image(systemName: "app").font(.system(size: side * 0.5)).foregroundStyle(.tertiary)
            .frame(width: side, height: side).background(.quinary, in: RoundedRectangle(cornerRadius: side * 0.2))
            .help("图标尚未取得；自定义服务可在编辑中导入图标")
    }
}

struct Pill: View {
    var text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .foregroundStyle(color).background(color.opacity(0.10), in: Capsule())
    }
}

struct Surface<Content: View>: View {
    var title: String
    var iconSources: [String] = []
    var iconStore: BrandIconStore? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let iconStore { BrandIconView(sources: iconSources, store: iconStore) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }
}

struct Fact: View {
    var title: String
    var value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.system(size: 12))
    }
}

struct PageHeading: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 25, weight: .bold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExternalOfferLink: View {
    var path: String
    var title = "查看最新优惠"
    var body: some View {
        if let url = URL(string: "https://deals.iplaysoft.com" + path) {
            Link(destination: url) {
                Label(title, systemImage: "arrow.up.right")
            }
        }
    }
}
