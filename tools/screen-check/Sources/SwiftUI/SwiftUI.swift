@_exported import Foundation
@_exported import Observation
import UniformTypeIdentifiers

// MARK: Core

@MainActor @preconcurrency public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Body { get }
}
extension Never: View { public var body: Never { fatalError() } }
public protocol _Primitive: View where Body == Never {}
extension _Primitive { public var body: Never { fatalError() } }

public struct EmptyView: _Primitive { public init() {} }
public struct TupleView<T>: _Primitive { init() {} }
public struct _ConditionalContent<A, B>: _Primitive { init() {} }
extension Optional: View where Wrapped: View { public var body: Never { fatalError() } }
public struct _Modified<V>: _Primitive { init() {} }

@resultBuilder public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<each C: View>(_ c: repeat each C) -> TupleView<(repeat each C)> { TupleView() }
    public static func buildExpression<C: View>(_ c: C) -> C { c }
    public static func buildIf<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<A: View, B: View>(first: A) -> _ConditionalContent<A, B> { _ConditionalContent() }
    public static func buildEither<A: View, B: View>(second: B) -> _ConditionalContent<A, B> { _ConditionalContent() }
}

@MainActor public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _Modified<Self>
    @ViewBuilder @MainActor func body(content: Content) -> Body
}
extension View { public func modifier<M: ViewModifier>(_ m: M) -> some View { self } }

// MARK: State

@propertyWrapper public struct State<Value> {
    final class Box { var value: Value; init(_ v: Value) { value = v } }
    let box: Box
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init(initialValue: Value) { box = Box(initialValue) }
    public var wrappedValue: Value { get { box.value } nonmutating set { box.value = newValue } }
    public var projectedValue: Binding<Value> { Binding(get: { box.value }, set: { box.value = $0 }) }
}

@propertyWrapper @dynamicMemberLookup public struct Binding<Value> {
    let getter: () -> Value, setter: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { getter = get; setter = set }
    public var wrappedValue: Value { get { getter() } nonmutating set { setter(newValue) } }
    public var projectedValue: Binding<Value> { self }
    public static func constant(_ v: Value) -> Binding<Value> { Binding(get: { v }, set: { _ in }) }
    public subscript<S>(dynamicMember kp: WritableKeyPath<Value, S>) -> Binding<S> {
        Binding<S>(get: { getter()[keyPath: kp] }, set: { var v = getter(); v[keyPath: kp] = $0; setter(v) })
    }
}

public struct DismissAction { public func callAsFunction() {} }
public enum ScenePhase { case active, inactive, background }
public struct EnvironmentValues {
    public var dismiss: DismissAction { DismissAction() }
    public var scenePhase: ScenePhase { .active }
}

@propertyWrapper public struct Environment<Value> {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {}
    public init(_ type: Value.Type) where Value: AnyObject & Observable {}
    public var wrappedValue: Value { fatalError() }
}

@propertyWrapper @dynamicMemberLookup public struct Bindable<Value: AnyObject & Observable> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(_ wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var projectedValue: Bindable<Value> { self }
    public subscript<S>(dynamicMember kp: ReferenceWritableKeyPath<Value, S>) -> Binding<S> {
        Binding<S>(get: { wrappedValue[keyPath: kp] }, set: { wrappedValue[keyPath: kp] = $0 })
    }
}

// MARK: Styles, colours, fonts

public protocol ShapeStyle {}
public struct Color: ShapeStyle, _Primitive, Hashable, Sendable {
    public static let orange = Color(), red = Color(), clear = Color(), black = Color(), white = Color()
    public static let secondary = Color(), primary = Color(), accentColor = Color()
    public init() {}
    public func opacity(_ o: Double) -> Color { self }
}
public struct HierarchicalShapeStyle: ShapeStyle { init() {} }
public struct Material: ShapeStyle { init() {} }
extension ShapeStyle where Self == Color {
    public static var orange: Color { Color() }
    public static var red: Color { Color() }
    public static var clear: Color { Color() }
    public static var black: Color { Color() }
}
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .init() }
    public static var secondary: HierarchicalShapeStyle { .init() }
    public static var tertiary: HierarchicalShapeStyle { .init() }
}
extension ShapeStyle where Self == Material { public static var thinMaterial: Material { .init() } }

public struct Font: Hashable, Sendable {
    public enum Weight: Sendable { case regular, medium, semibold, bold }
    public enum Design: Sendable { case `default`, serif, monospaced, rounded }
    public enum TextStyle: Sendable { case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2 }
    public static let largeTitle = Font(), title = Font(), title2 = Font(), title3 = Font(), headline = Font(), subheadline = Font()
    public static let body = Font(), callout = Font(), footnote = Font(), caption = Font(), caption2 = Font()
    public static func system(size: CGFloat, weight: Weight? = nil, design: Design? = nil) -> Font { Font() }
    public static func custom(_ name: String, size: CGFloat, relativeTo: TextStyle) -> Font { Font() }
    public func weight(_ w: Weight) -> Font { self }
    public func bold() -> Font { self }
    public func monospaced() -> Font { self }
    public func monospacedDigit() -> Font { self }
}

public enum Visibility: Sendable { case automatic, visible, hidden }
public enum HorizontalEdge: Sendable { case leading, trailing }
public enum VerticalEdge: Sendable { case top, bottom
    public struct Set: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1), bottom = Set(rawValue: 2), all: Set = [.top, .bottom] } }
public enum Edge: Sendable { case top, bottom, leading, trailing
    public struct Set: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1), bottom = Set(rawValue: 2), leading = Set(rawValue: 4), trailing = Set(rawValue: 8)
        public static let horizontal: Set = [.leading, .trailing], vertical: Set = [.top, .bottom], all: Set = [.horizontal, .vertical] } }
public enum Axis: Sendable { case horizontal, vertical
    public struct Set: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1), vertical = Set(rawValue: 2) } }
public struct HorizontalAlignment: Sendable { public static let leading = HorizontalAlignment(), center = HorizontalAlignment(), trailing = HorizontalAlignment() }
public struct VerticalAlignment: Sendable { public static let top = VerticalAlignment(), center = VerticalAlignment(), bottom = VerticalAlignment(), firstTextBaseline = VerticalAlignment() }
public struct Alignment: Sendable { public static let center = Alignment(), leading = Alignment(), trailing = Alignment(), top = Alignment(), bottom = Alignment(), topLeading = Alignment() }
public enum TextAlignment: Sendable { case leading, center, trailing }
public struct UnitPoint: Sendable { public static let top = UnitPoint(), bottom = UnitPoint(), center = UnitPoint() }
public struct SafeAreaRegions: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let all = SafeAreaRegions(rawValue: 1) }
public struct LocalizedStringKey: ExpressibleByStringInterpolation { public init(stringLiteral value: String) {}; public init(_ value: String) {} }

// MARK: Shapes

public protocol Shape: View {}
extension Shape {
    public func fill<S: ShapeStyle>(_ s: S) -> some View { self }
    public func stroke<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> some View { self }
}
public struct Rectangle: Shape, _Primitive { public init() {} }
public struct RoundedRectangle: Shape, _Primitive { public init(cornerRadius: CGFloat) {} }
public struct Capsule: Shape, _Primitive { public init() {} }

// MARK: Views

public struct Text: _Primitive {
    public enum Case: Sendable { case uppercase, lowercase }
    public init(_ key: LocalizedStringKey) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ s: S) {}
    public init(verbatim: String) {}
}
public struct Image: _Primitive { public init(systemName: String) {} }
public struct Label<Title: View, Icon: View>: _Primitive {}
extension Label where Title == Text, Icon == Image {
    public init(_ key: LocalizedStringKey, systemImage: String) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage: String) {}
}
public struct ButtonRole: Sendable { public static let destructive = ButtonRole(), cancel = ButtonRole() }
public struct Button<L: View>: _Primitive {
    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> L) {}
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> L) {}
}
extension Button where L == Text {
    public init(_ key: LocalizedStringKey, action: @escaping @MainActor () -> Void) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {}
    public init(_ key: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {}
}
extension Button where L == Label<Text, Image> {
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {}
}
public struct Toggle<L: View>: _Primitive { public init(isOn: Binding<Bool>, @ViewBuilder label: () -> L) {} }
extension Toggle where L == Text {
    public init(_ key: LocalizedStringKey, isOn: Binding<Bool>) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {}
}
public struct Picker<L: View, V: Hashable, C: View>: _Primitive {
    public init(selection: Binding<V>, @ViewBuilder content: () -> C, @ViewBuilder label: () -> L) {}
}
extension Picker where L == Text {
    public init(_ key: LocalizedStringKey, selection: Binding<V>, @ViewBuilder content: () -> C) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, selection: Binding<V>, @ViewBuilder content: () -> C) {}
}
public struct TextField<L: View>: _Primitive {}
extension TextField where L == Text {
    public init(_ key: LocalizedStringKey, text: Binding<String>) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>) {}
    public init(_ key: LocalizedStringKey, text: Binding<String>, axis: Axis) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) {}
}
public struct ProgressView: _Primitive {
    public init() {}
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {}
}
public struct Link<L: View>: _Primitive { public init(destination: URL, @ViewBuilder label: () -> L) {} }
public struct Menu<L: View, C: View>: _Primitive { public init(@ViewBuilder content: () -> C, @ViewBuilder label: () -> L) {} }
public struct ShareLink: _Primitive { public init(item: String) {} }
public struct Spacer: _Primitive { public init(minLength: CGFloat? = nil) {} }
public struct Divider: _Primitive { public init() {} }
public struct EditButton: _Primitive { public init() {} }
public struct Group<C: View>: _Primitive { public init(@ViewBuilder content: () -> C) {} }
public struct HStack<C: View>: _Primitive { public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> C) {} }
public struct VStack<C: View>: _Primitive { public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> C) {} }
public struct ZStack<C: View>: _Primitive { public init(alignment: Alignment = .center, @ViewBuilder content: () -> C) {} }
public struct ScrollView<C: View>: _Primitive { public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> C) {} }
public struct ScrollViewProxy { public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {} }
public struct ScrollViewReader<C: View>: _Primitive { public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> C) {} }
public struct List<C: View>: _Primitive { public init(@ViewBuilder content: () -> C) {} }
public struct Form<C: View>: _Primitive { public init(@ViewBuilder content: () -> C) {} }
public struct Section<P: View, C: View, F: View>: _Primitive {
    public init(@ViewBuilder content: () -> C, @ViewBuilder header: () -> P, @ViewBuilder footer: () -> F) {}
}
extension Section where P == EmptyView, F == EmptyView { public init(@ViewBuilder content: () -> C) {} }
extension Section where F == EmptyView { public init(@ViewBuilder content: () -> C, @ViewBuilder header: () -> P) {} }
extension Section where P == EmptyView { public init(@ViewBuilder content: () -> C, @ViewBuilder footer: () -> F) {} }
extension Section where P == Text, F == EmptyView {
    public init(_ key: LocalizedStringKey, @ViewBuilder content: () -> C) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> C) {}
}
public protocol DynamicViewContent: View {}
extension DynamicViewContent {
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> some DynamicViewContent { self }
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> some DynamicViewContent { self }
}
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, C: View>: DynamicViewContent, _Primitive {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> C) {}
}
extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> C) {}
}
extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> C) {}
}
public struct NavigationStack<Path, Root: View>: _Primitive {}
extension NavigationStack where Path == Never { public init(@ViewBuilder root: () -> Root) {} }
extension NavigationStack {
    public init(path: Binding<Path>, @ViewBuilder root: () -> Root)
        where Path: MutableCollection & RandomAccessCollection & RangeReplaceableCollection, Path.Element: Hashable {}
}
public struct NavigationLink<L: View, D: View>: _Primitive {
    public init(@ViewBuilder destination: () -> D, @ViewBuilder label: () -> L) {}
}
public struct LabeledContent<L: View, C: View>: _Primitive {}
extension LabeledContent where L == Text, C == Text {
    public init(_ key: LocalizedStringKey, value: String) {}
    @_disfavoredOverload public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {}
}
extension LabeledContent where L == Text {
    public init(_ key: LocalizedStringKey, @ViewBuilder content: () -> C) {}
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> C) {}
}

// MARK: Toolbar

public protocol ToolbarContent {}
public struct ToolbarItemPlacement: Sendable { public static let topBarTrailing = ToolbarItemPlacement(), topBarLeading = ToolbarItemPlacement(), automatic = ToolbarItemPlacement() }
public struct ToolbarItem<C: View>: ToolbarContent { public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> C) {} }
public struct ToolbarItemGroup<C: View>: ToolbarContent { public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> C) {} }
public struct _ToolbarTuple: ToolbarContent {}
extension Optional: ToolbarContent where Wrapped: ToolbarContent {}
@resultBuilder public struct ToolbarContentBuilder {
    public static func buildBlock<C: ToolbarContent>(_ c: C) -> C { c }
    public static func buildBlock<each C: ToolbarContent>(_ c: repeat each C) -> _ToolbarTuple { _ToolbarTuple() }
    public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
}
public struct ToolbarPlacement: Sendable { public static let navigationBar = ToolbarPlacement(), tabBar = ToolbarPlacement() }

// MARK: Gestures and layout

public protocol Gesture { associatedtype Value }
public struct DragGesture: Gesture {
    public struct Value { public var location: CGPoint; public var translation: CGSize }
    public init(minimumDistance: CGFloat = 10) {}
}
extension Gesture {
    public func onChanged(_ action: @escaping (Value) -> Void) -> Self { self }
    public func onEnded(_ action: @escaping (Value) -> Void) -> Self { self }
}

public struct ProposedViewSize: Sendable {
    public var width: CGFloat?, height: CGFloat?
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public init(width: CGFloat?, height: CGFloat?) { self.width = width; self.height = height }
    public init(_ size: CGSize) { width = size.width; height = size.height }
}
public struct LayoutSubview {
    public func sizeThatFits(_ p: ProposedViewSize) -> CGSize { .zero }
    public func place(at: CGPoint, anchor: UnitPoint = .center, proposal: ProposedViewSize) {}
}
public struct LayoutSubviews: RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { 0 }
    public subscript(i: Int) -> LayoutSubview { LayoutSubview() }
}
@MainActor public protocol Layout {
    associatedtype Cache = Void
    typealias Subviews = LayoutSubviews
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}
extension Layout { public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View { EmptyView() } }

// MARK: Styles for controls

public protocol PrimitiveButtonStyle {}
public struct BorderlessButtonStyle: PrimitiveButtonStyle {}
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle {}
public struct PlainButtonStyle: PrimitiveButtonStyle {}
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: Self { .init() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle { public static var borderedProminent: Self { .init() } }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: Self { .init() } }
public protocol PickerStyle {}
public struct SegmentedPickerStyle: PickerStyle {}
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: Self { .init() } }
public protocol ListStyle {}
public struct PlainListStyle: ListStyle {}
extension ListStyle where Self == PlainListStyle { public static var plain: Self { .init() } }
public protocol TextSelectability {}
public struct EnabledTextSelectability: TextSelectability {}
extension TextSelectability where Self == EnabledTextSelectability { public static var enabled: Self { .init() } }
public struct TextInputAutocapitalization: Sendable { public static let never = TextInputAutocapitalization(), sentences = TextInputAutocapitalization() }
public struct AccessibilityTraits: OptionSet, Sendable { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let isHeader = AccessibilityTraits(rawValue: 1) }
public struct NavigationBarItem { public enum TitleDisplayMode: Sendable { case automatic, inline, large } }
public struct ScrollDismissesKeyboardMode: Sendable { public static let immediately = ScrollDismissesKeyboardMode(), interactively = ScrollDismissesKeyboardMode() }
public struct SearchFieldPlacement: Sendable {
    public enum NavigationBarDrawerDisplayMode: Sendable { case automatic, always }
    public static let automatic = SearchFieldPlacement()
    public static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement { .init() }
}
public enum ColorScheme: Sendable { case light, dark }

// MARK: Modifiers

extension View {
    public func font(_ f: Font?) -> some View { self }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> some View { self }
    public func tint(_ c: Color?) -> some View { self }
    @_disfavoredOverload public func tint<S: ShapeStyle>(_ s: S?) -> some View { self }
    public func padding(_ length: CGFloat) -> some View { self }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { self }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
                      idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    public func background<S: ShapeStyle>(_ s: S, ignoresSafeAreaEdges: Edge.Set = .all) -> some View { self }
    public func background<S: ShapeStyle, T: Shape>(_ s: S, in shape: T) -> some View { self }
    public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    public func overlay<S: ShapeStyle>(_ s: S, ignoresSafeAreaEdges: Edge.Set = .all) -> some View { self }
    @_disfavoredOverload public func overlay<V: View>(_ overlay: V, alignment: Alignment = .center) -> some View { self }
    public func opacity(_ o: Double) -> some View { self }
    public func lineLimit(_ n: Int?) -> some View { self }
    public func lineLimit(_ r: ClosedRange<Int>) -> some View { self }
    public func multilineTextAlignment(_ a: TextAlignment) -> some View { self }
    public func textCase(_ c: Text.Case?) -> some View { self }
    public func disabled(_ d: Bool) -> some View { self }
    public func buttonStyle<S: PrimitiveButtonStyle>(_ s: S) -> some View { self }
    public func pickerStyle<S: PickerStyle>(_ s: S) -> some View { self }
    public func listStyle<S: ListStyle>(_ s: S) -> some View { self }
    public func labelsHidden() -> some View { self }
    public func listRowBackground<V: View>(_ v: V?) -> some View { self }
    public func listRowSeparator(_ v: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
    public func scrollContentBackground(_ v: Visibility) -> some View { self }
    public func scrollDismissesKeyboard(_ m: ScrollDismissesKeyboardMode) -> some View { self }
    public func navigationTitle(_ key: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload public func navigationTitle<S: StringProtocol>(_ s: S) -> some View { self }
    public func navigationBarTitleDisplayMode(_ m: NavigationBarItem.TitleDisplayMode) -> some View { self }
    public func navigationDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View { self }
    public func navigationDestination<D: Hashable, C: View>(item: Binding<D?>, @ViewBuilder destination: @escaping (D) -> C) -> some View { self }
    public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> some View { self }
    public func toolbar(_ v: Visibility, for bars: ToolbarPlacement...) -> some View { self }
    public func toolbarBackground<S: ShapeStyle>(_ s: S, for bars: ToolbarPlacement...) -> some View { self }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload public func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> some View { self }
    public func textInputAutocapitalization(_ a: TextInputAutocapitalization?) -> some View { self }
    public func autocorrectionDisabled(_ d: Bool = true) -> some View { self }
    public func swipeActions<V: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> V) -> some View { self }
    public func contextMenu<V: View>(@ViewBuilder menuItems: () -> V) -> some View { self }
    public func confirmationDialog<S: StringProtocol, A: View, M: View>(
        _ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View { self }
    public func confirmationDialog<S: StringProtocol, A: View, M: View, T>(
        _ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
        @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View { self }
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                             onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View { self }
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                             onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View { self }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { self }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View { self }
    public func task<T: Equatable>(id: T, priority: TaskPriority = .userInitiated,
                                   @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View { self }
    public func task(priority: TaskPriority = .userInitiated, @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View { self }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { self }
    public func accessibilityLabel(_ key: LocalizedStringKey) -> some View { self }
    @_disfavoredOverload public func accessibilityLabel<S: StringProtocol>(_ s: S) -> some View { self }
    public func accessibilityHidden(_ h: Bool) -> some View { self }
    public func accessibilityAddTraits(_ t: AccessibilityTraits) -> some View { self }
    public func textSelection<S: TextSelectability>(_ s: S) -> some View { self }
    public func tag<V: Hashable>(_ v: V) -> some View { self }
    public func id<ID: Hashable>(_ id: ID) -> some View { self }
    public func contentShape<S: Shape>(_ s: S) -> some View { self }
    public func gesture<G: Gesture>(_ g: G) -> some View { self }
    public func onTapGesture(count: Int = 1, perform: @escaping () -> Void) -> some View { self }
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some View { self }
    public func preferredColorScheme(_ s: ColorScheme?) -> some View { self }
}

extension RangeReplaceableCollection where Self: MutableCollection, Index == Int {
    public mutating func remove(atOffsets offsets: IndexSet) { for i in offsets.reversed() { remove(at: i) } }
}
extension MutableCollection where Index == Int {
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {}
}
