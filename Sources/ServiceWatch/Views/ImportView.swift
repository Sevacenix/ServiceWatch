import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Bindable var store: DemoStore
    var inSheet: Bool
    @State private var dropActive = false
    @State private var pastedText = ""
    @State private var recognition: ImportRecognition?
    @State private var candidateID: UUID?
    @State private var draft: AuthorizationImportDraft?
    @State private var confirmed = false
    @State private var error: String?
    @State private var savedID: Int?
    @State private var operation: Task<Void, Never>?

    private var personalServices: [Service] { store.services.filter { !$0.example } }
    private var fileTypes: [UTType] {
        let mailTypes = UTType.types(tag: "eml", tagClass: .filenameExtension, conformingTo: nil)
        return (mailTypes.isEmpty ? [.emailMessage] : mailTypes) + [.png, .jpeg, .heic, .tiff] +
            [UTType(filenameExtension: "heif")].compactMap { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    PageHeading(title: "授权导入", subtitle: "从邮件或截图识别服务、等级与有效期。核对后再保存。")
                    if inSheet {
                        Button("关闭") { store.showingImport = false }.keyboardShortcut(.cancelAction)
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if operation != nil {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("正在本机读取和识别…")
                        Button("取消") { cancelOperation() }
                    }.padding(.vertical, 20)
                } else if let recognition, let binding = Binding($draft) {
                    review(recognition, draft: binding)
                } else {
                    intake
                }
                Label("仅在本机处理。保存已确认字段和来源类型，不保存邮件、图片或识别全文。", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onChange(of: draft) { _, _ in confirmed = false }
        .onDisappear { cancelOperation() }
    }

    private var intake: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 13) {
                Image(systemName: "doc.viewfinder").font(.system(size: 35)).foregroundStyle(.tint)
                Text("拖入一封邮件或一张截图").font(.title3.weight(.semibold))
                Text(".eml 或 PNG、JPEG、HEIC、TIFF").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("选择文件…", action: chooseFile).buttonStyle(.borderedProminent)
                    Button("粘贴截图") { pasteImage() }
                }
            }
            .frame(maxWidth: .infinity).padding(24)
            .background(dropActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(dash: [6, 4])))
            .dropDestination(for: URL.self) { urls, _ in
                guard urls.count == 1, let url = urls.first, url.isFileURL else {
                    error = "每次请选择一个本地邮件或截图。"
                    return false
                }
                open(url)
                return true
            } isTargeted: { dropActive = $0 }
            Surface(title: "粘贴邮件正文") {
                TextEditor(text: $pastedText)
                    .font(.callout).frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if pastedText.isEmpty {
                            Text("例如：产品名称、授权等级和明确到期日")
                                .foregroundStyle(.tertiary).padding(6).allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("邮件正文")
                Button("识别邮件正文") {
                    let text = pastedText
                    start { ImportDocument(text: text) }
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pastedText.count > ImportInput.textLimit)
                if pastedText.count > ImportInput.textLimit {
                    Text("正文过长，请只粘贴与授权有关的段落。").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func review(_ result: ImportRecognition, draft value: Binding<AuthorizationImportDraft>) -> some View {
        let current = value.wrappedValue
        let service = personalServices.first { $0.id == current.serviceID }
        let candidate = result.candidates.first { $0.id == candidateID }
        let matchingDates = result.candidates.filter { !$0.tier.isEmpty && $0.tier == candidate?.tier }.count
        let validation = Result { try store.prepareImport(current) }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(result.origin.rawValue + " · 核对识别结果", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button("重新导入") { clearReview() }
            }
            if result.ambiguousService {
                Text("材料中出现多个服务名，请选择对应服务。").font(.callout).foregroundStyle(.orange)
            }
            if result.candidates.count > 1 {
                Picker("识别到的授权", selection: Binding(get: { candidateID }, set: { id in
                    if let item = result.candidates.first(where: { $0.id == id }) { select(item, from: result) }
                })) {
                    ForEach(result.candidates) { item in
                        Text("\(item.tier.isEmpty ? "等级待确认" : item.tier) · \(item.perpetual ? "永久授权" : item.expiry ?? "日期待确认")")
                            .tag(Optional(item.id))
                    }
                }
                Text("每次保存一条；可切换候选结果继续核对。").font(.caption).foregroundStyle(.secondary)
            }
            if matchingDates > 1 {
                Label("同一等级识别到多个有效期，请核对当前生效的日期。", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            Surface(title: "原文依据 · 已隐藏常见敏感内容") {
                Text(candidate.flatMap { $0.evidence.isEmpty ? nil : $0.evidence } ?? "没有提取到明确的授权依据。")
                    .font(.callout).textSelection(.enabled)
                DisclosureGroup("查看识别文本") {
                    ScrollView {
                        Text(result.excerpt.isEmpty ? "无可显示内容" : result.excerpt)
                            .font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 140)
                }
            }
            Surface(title: "核对并保存") {
                Picker("保存到服务", selection: Binding(get: { current.serviceID }, set: { id in
                    let chosen = personalServices.first { $0.id == id }
                    value.wrappedValue.serviceID = id
                    value.wrappedValue.serviceName = chosen?.name ?? result.service ?? ""
                    value.wrappedValue.target = (chosen?.entitlements.isEmpty ?? true) ? .add : .choose
                    value.wrappedValue.baseline = nil
                    value.wrappedValue.markPaid = chosen == nil
                    savedID = nil
                })) {
                    Text("新增服务").tag(nil as Int?)
                    ForEach(personalServices) { service in Text(service.name).tag(Optional(service.id)) }
                }
                if service == nil { TextField("服务名称", text: value.serviceName) }
                if let service, !service.entitlements.isEmpty {
                    Picker("授权记录", selection: Binding(get: { current.target }, set: { target in
                        value.wrappedValue = current.selection(target, in: service)
                        savedID = nil
                    })) {
                        Text("请选择").tag(ImportTarget.choose)
                        Text("新增等级").tag(ImportTarget.add)
                        ForEach(service.entitlements) { item in
                            Text("更新 \(item.tier) · \(item.perpetual ? "永久" : item.expires ?? "待确认")")
                                .tag(ImportTarget.update(item.id))
                        }
                    }
                }
                TextField("服务等级", text: value.tier)
                Picker("有效期", selection: value.validity) {
                    ForEach(["有到期日", "永久授权", "待确认"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                if current.validity == "有到期日" {
                    TextField("到期日（YYYY-MM-DD）", text: value.expiry)
                } else if current.validity == "待确认" {
                    Text("只显示天数、续费日或购买日期时，需核对实际到期日。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if service?.paid != true {
                    Toggle("列为已开通", isOn: value.markPaid).font(.callout)
                }
                if let before = current.baseline {
                    Fact(title: "将更新的授权",
                         value: "\(before.tier) · \(before.perpetual ? "永久授权" : before.expires ?? "待确认") → \(current.cleanTier) · \(current.validitySummary)")
                    Text("其他等级、实付金额和自动扣款设置保持原样。").font(.caption).foregroundStyle(.secondary)
                    if current.validity == "有到期日", let oldExpiry = before.expires,
                       current.validFields && current.cleanExpiry < oldExpiry {
                        Text("导入日期早于现有到期日，请核对是否为历史记录。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if case .failure(let issue) = validation, current.validFields, savedID == nil {
                    Text(issue.localizedDescription).font(.caption).foregroundStyle(.orange)
                }
                if let savedID {
                    HStack {
                        Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("查看授权记录") {
                            store.selectedID = savedID
                            store.destination = .services
                            store.showingImport = false
                        }
                    }.font(.callout)
                } else {
                    Toggle("我已核对服务、等级、到期日与保存目标", isOn: $confirmed).font(.callout)
                    Button("保存此授权") {
                        do {
                            savedID = try store.saveImport(current)
                            confirmed = false
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!confirmed || (try? validation.get()) == nil || store.storageIssue != nil)
                }
            }.onChange(of: current) { _, _ in savedID = nil }
        }
    }

    private func select(_ candidate: RecognizedAuthorization, from result: ImportRecognition) {
        candidateID = candidate.id
        let service = result.service.flatMap { name in
            let matches = personalServices.filter { AuthorizationRecognition.key($0.name) == AuthorizationRecognition.key(name) }
            return matches.count == 1 ? matches.first : nil
        }
        draft = .init(origin: result.origin, name: service?.name ?? result.service ?? "", service: service, candidate: candidate)
        confirmed = false
        savedID = nil
        error = nil
    }

    private func open(_ url: URL) { start { try ImportInput.read(url) } }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = "选择一封授权邮件或一张会员截图"
        panel.prompt = "识别"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = fileTypes
        let didChoose: (NSApplication.ModalResponse) -> Void = { result in
            if result == .OK, let url = panel.url { open(url) }
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: didChoose)
        } else {
            panel.begin(completionHandler: didChoose)
        }
    }

    private func pasteImage() {
        let board = NSPasteboard.general
        guard let image = board.data(forType: .init("public.png")) ?? board.data(forType: .tiff) else {
            error = "剪贴板里没有图片。请复制截图，或直接选择图片文件。"
            return
        }
        start { try ImportInput.recognize(image) }
    }

    private func start(_ read: @escaping @Sendable () throws -> ImportDocument) {
        guard operation == nil else { return }
        clearReview()
        let names = personalServices.map(\.name) +
            store.catalog.snapshot.products.filter { $0.listed && !$0.path.hasPrefix("/bundle/") }.map(\.name)
        let worker = Task.detached(priority: .userInitiated) {
            try AuthorizationRecognition.recognize(read(), names: names)
        }
        operation = Task {
            let result = await withTaskCancellationHandler { await worker.result } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            operation = nil
            switch result {
            case .success(let extracted):
                recognition = extracted
                pastedText = ""
                if let first = extracted.candidates.first { select(first, from: extracted) }
            case .failure(let issue): error = issue.localizedDescription
            }
        }
    }

    private func cancelOperation() {
        operation?.cancel()
        operation = nil
    }

    private func clearReview() {
        recognition = nil
        candidateID = nil
        draft = nil
        savedID = nil
        confirmed = false
        error = nil
    }
}
