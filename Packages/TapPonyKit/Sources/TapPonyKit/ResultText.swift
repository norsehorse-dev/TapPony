import Foundation

/// Custom success and failure text, PROFILE_SCHEMA.md section 15. Mirrors com.tappony.core.ResultText.
public enum ResultText {
    public static let cap = 200

    public static func render(_ template: String?, status: Int?, message: String?, uid: String, profile: String) -> String? {
        guard let template, !template.isEmpty else { return nil }
        let vars = ["status": status.map { String($0) } ?? "", "message": message ?? "", "uid": uid, "profile": profile]
        let out = (try? Template.render(template, context: .raw, variables: vars)) ?? template
        return Encoding.capCodePoints(out, cap)
    }
}
