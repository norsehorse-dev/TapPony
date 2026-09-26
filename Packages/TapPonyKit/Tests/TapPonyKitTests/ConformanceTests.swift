import XCTest
@testable import TapPonyKit

/// Runs the shared conformance fixtures from the repo root (fixtures/). The
/// Android core runs the same files; both must stay green.
final class ConformanceTests: XCTestCase {

    private func fixture(_ name: String) throws -> JSONValue {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TapPonyKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // TapPonyKit
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
        let data = try Data(contentsOf: root.appendingPathComponent("fixtures").appendingPathComponent(name))
        return try JSON.parse(String(decoding: data, as: UTF8.self))
    }

    private func strMap(_ v: JSONValue?) -> [String: String] {
        guard case .object(let members)? = v else { return [:] }
        var out: [String: String] = [:]
        for m in members { out[m.key] = m.value.string ?? "" }
        return out
    }

    private func hex(_ s: String?) -> [UInt8]? {
        guard let s else { return nil }
        return Encoding.parseHex(s)!
    }

    func testTemplates() throws {
        let f = try fixture("template_vectors.json")
        let vars = strMap(f["variables"])
        let secrets = strMap(f["secrets"])
        let cases = f["cases"]?.array ?? []
        XCTAssertGreaterThan(cases.count, 50)
        for c in cases {
            let id = c["id"]!.string!
            let ctx = TemplateContext(rawValue: c["context"]!.string!)!
            let expectErr = c["error"]?.string
            do {
                let out = try Template.render(c["template"]!.string!, context: ctx, variables: vars, secrets: secrets)
                XCTAssertNil(expectErr, "\(id): expected error, got \(out)")
                XCTAssertEqual(out, c["output"]?.string, id)
            } catch let e as TemplateError {
                XCTAssertEqual(e.code, expectErr, id)
            }
        }
    }

    func testHostPolicy() throws {
        let f = try fixture("hostpolicy_vectors.json")
        for c in f["cases"]?.array ?? [] {
            let url = c["url"]!.string!
            let r = HostPolicy.check(url, allowLocalHttp: c["allowLocalHttp"]!.bool!)
            XCTAssertEqual(r.allowed ? "allowed" : "rejected", c["verdict"]!.string!, url)
            XCTAssertEqual(r.detail, c["detail"]!.string!, url)
        }
        for c in f["templateCases"]?.array ?? [] {
            XCTAssertEqual(HostPolicy.checkTemplate(c["template"]!.string!), c["result"]!.string!)
        }
    }

    func testUids() throws {
        let f = try fixture("uid_vectors.json")
        for c in f["cases"]?.array ?? [] {
            let fam = TagFamily(rawValue: c["family"]!.string!)!
            XCTAssertEqual(Uid.variables(fam, hex(c["raw"]!.string!)!), strMap(c["expect"]), c["raw"]!.string!)
        }
        for c in f["chips"]?.array ?? [] {
            let b = hex(c["response"]!.string!)!
            let got = c["kind"]!.string! == "getVersion" ? Uid.chipFromGetVersion(b) : Uid.chipFromDesfireVersion(b)
            XCTAssertEqual(got, c["chip"]!.string!, c["response"]!.string!)
        }
    }

    func testSigning() throws {
        let f = try fixture("signing_vectors.json")
        for c in f["cases"]?.array ?? [] {
            XCTAssertEqual(Signing.signature(key: c["key"]!.string!, timestamp: c["timestamp"]!.string!, body: c["body"]!.string!),
                           c["signature"]!.string!)
        }
    }

    func testVariables() throws {
        let f = try fixture("variables_vectors.json")
        for c in f["cases"]?.array ?? [] {
            let r = c["reading"]!
            let x = c["context"]!
            var reading = TagReading(family: TagFamily(rawValue: r["family"]!.string!)!, tagType: r["tagType"]!.string!,
                                     identifier: hex(r["identifier"]!.string!)!)
            reading.chip = r["chip"]?.string ?? ""
            reading.signature = hex(r["signature"]?.string)
            reading.counter = r["counter"]?.int
            reading.atqa = hex(r["atqa"]?.string)
            reading.sak = hex(r["sak"]?.string)
            reading.dsfid = hex(r["dsfid"]?.string)
            reading.afi = hex(r["afi"]?.string)
            reading.blockSize = r["blockSize"]?.int
            reading.blockCount = r["blockCount"]?.int
            reading.pmm = hex(r["pmm"]?.string)
            reading.systemCode = hex(r["systemCode"]?.string)
            reading.historicalBytes = hex(r["historicalBytes"]?.string)
            reading.applicationData = hex(r["applicationData"]?.string)
            reading.ndef = (r["ndef"]?.array ?? []).map {
                NdefRecord(tnf: $0["tnf"]!.int!, type: hex($0["type"]!.string!)!, id: hex($0["id"]?.string ?? "")!, payload: hex($0["payload"]!.string!)!)
            }
            let ctx = SendContext(
                scanTimeMs: Int64(x["scanTimeMs"]!.int!), sendTimeMs: Int64(x["sendTimeMs"]!.int!), timeZone: x["tz"]!.string!,
                profileName: x["profileName"]!.string!, profileId: x["profileId"]!.string!, deviceLabel: x["deviceLabel"]?.string ?? "",
                platform: x["platform"]!.string!, nonce: x["nonce"]!.string!, seq: Int64(x["seq"]!.int!), tagLabel: x["tagLabel"]?.string ?? "")
            let got = Variables.build(reading, ctx)
            let expect = strMap(c["expect"])
            let id = c["id"]!.string!
            XCTAssertEqual(Set(got.keys), Set(expect.keys), id)
            XCTAssertEqual(Set(got.keys), Variables.all, id)
            for (k, v) in expect { XCTAssertEqual(got[k], v, "\(id).\(k)") }
        }
    }

    func testRequests() throws {
        let f = try fixture("request_vectors.json")
        let vars = strMap(f["variables"])
        let secrets = strMap(f["secrets"])
        for c in f["cases"]?.array ?? [] {
            let id = c["id"]!.string!
            let profile = try ProfileCodec.fromJSON(c["profile"]!)
            let expectErr = c["error"]?.string
            do {
                let got = try RequestBuilder.build(profile, variables: vars, secrets: secrets, sendUnix: Int64(c["sendUnix"]!.int!))
                XCTAssertNil(expectErr, "\(id): expected \(expectErr ?? "")")
                let e = c["expect"]!
                XCTAssertEqual(got.method, e["method"]!.string!, id)
                XCTAssertEqual(got.url, e["url"]!.string!, id)
                let eh = (e["headers"]!.array ?? []).map { "\($0.array![0].string!): \($0.array![1].string!)" }
                XCTAssertEqual(got.headers.map { "\($0.0): \($0.1)" }, eh, id)
                XCTAssertEqual(got.body, e["body"]?.string, id)
            } catch let err as RequestError {
                XCTAssertEqual(err.code, expectErr, id)
            }
        }
    }

    func testProfileRoundTrip() throws {
        let f = try fixture("request_vectors.json")
        for c in f["cases"]?.array ?? [] {
            let p = try ProfileCodec.fromJSON(c["profile"]!)
            XCTAssertEqual(try ProfileCodec.decode(ProfileCodec.encode(p)), p)
        }
        let withUnknown = "{\"schema\":1,\"id\":\"A\",\"name\":\"n\",\"future\":{\"x\":1},\"request\":{\"method\":\"GET\",\"url\":\"https://e.com\",\"newThing\":true}}"
        XCTAssertEqual(try ProfileCodec.decode(withUnknown).request.method, "GET")
        XCTAssertThrowsError(try ProfileCodec.decode("{\"schema\":2,\"id\":\"A\",\"name\":\"n\"}")) {
            XCTAssertEqual(($0 as? ProfileError)?.code, "newerSchema")
        }
    }

    func testPresetsAreValid() throws {
        let vars = Variables.sample(SendContext(scanTimeMs: 0, sendTimeMs: 0, timeZone: "UTC", profileName: "p", profileId: "id",
                                                deviceLabel: "", platform: "ios", nonce: "00", seq: 1))
        for p in Presets.all {
            let profile = p.create("ID")
            XCTAssertEqual(HostPolicy.checkTemplate(profile.request.url), "ok", p.key)
            var secrets: [String: String] = [:]
            for s in RequestBuilder.requiredSecrets(profile) { secrets[s] = "x" }
            let req = try RequestBuilder.build(profile, variables: vars, secrets: secrets, sendUnix: 0)
            XCTAssertTrue(req.url.hasPrefix("http"), p.key)
            XCTAssertEqual(try ProfileCodec.decode(ProfileCodec.encode(profile)), profile, p.key)
        }
    }

    func testJSONStrictness() {
        for bad in ["", "{", "[1,]", "{\"a\":1,}", "01", "1.", ".5", "NaN", "\"\u{01}\"", "{\"a\" 1}", "tru", "[1] [2]", "\"\\x\""] {
            XCTAssertFalse(JSON.isValid(bad), bad)
        }
        for good in ["0", "-0.5e+3", " {\"a\":[1,true,null,\"\\u00e9\"]} ", "\"\\ud83d\\udc34\"", "[]", "{}"] {
            XCTAssertTrue(JSON.isValid(good), good)
        }
    }

    /// Cross-platform byte check: the Android core writes profiles with the same
    /// key order, so an encoded preset must match this literal on both sides.
    func testProfileEncodingIsStable() {
        let p = Presets.byKey("generic_get")!.create("ID")
        XCTAssertEqual(ProfileCodec.encode(p),
            "{\"schema\":1,\"id\":\"ID\",\"name\":\"GET with query\",\"request\":{\"method\":\"GET\",\"url\":\"https://example.com/REPLACE_ME?uid={uid}&t={timestamp}\",\"headers\":[],\"body\":{\"type\":\"none\",\"template\":\"\",\"contentType\":null,\"fields\":[]},\"timeoutSeconds\":15,\"followRedirects\":false,\"allowLocalHttp\":false},\"auth\":{\"type\":\"none\"},\"signing\":{\"enabled\":false,\"secret\":null},\"tag\":{\"technologies\":[\"iso14443\",\"iso15693\",\"felica\"],\"extendedReads\":true,\"requireNdef\":false},\"after\":{\"messageField\":null,\"keepBodies\":false,\"sound\":true,\"haptic\":true,\"queueOffline\":false,\"successText\":null,\"failureText\":null,\"speak\":false}}")
    }

    func testResponseMessages() throws {
        let f = try fixture("message_vectors.json")
        for c in f["cases"]?.array ?? [] {
            let headers = (c["headers"]?.array ?? []).map { ($0.array![0].string!, $0.array![1].string!) }
            let got = ResponseMessage.extract(field: c["field"]?.string, headers: headers, body: c["body"]?.string)
            XCTAssertEqual(got, c["expect"]?.string, c["field"]?.string ?? "nil")
        }
    }

    func testHistoryCsv() throws {
        let f = try fixture("history_csv_vectors.json")
        let rows = (f["rows"]?.array ?? []).map { r in
            HistoryRow(timeMs: Int64(r["timeMs"]!.int!), profile: r["profile"]!.string!, uid: r["uid"]!.string!,
                       chip: r["chip"]!.string!, tagType: r["tagType"]!.string!, outcome: r["outcome"]!.string!,
                       status: r["status"]?.int, latencyMs: r["latencyMs"]?.int.map { Int64($0) }, error: r["error"]?.string ?? "")
        }
        XCTAssertEqual(HistoryCsv.document(rows), f["csv"]!.string!)
        for o in f["outcomes"]?.array ?? [] {
            XCTAssertEqual(HistoryCsv.outcome(buildError: o["buildError"]?.string, status: o["status"]?.int), o["outcome"]!.string!)
        }
    }

    func testRules() throws {
        let f = try fixture("rules_vectors.json")
        let base = try Rules.fromJSON(f["ruleset"]!)
        XCTAssertEqual(Rules.encode(base), f["encoded"]!.string!)
        XCTAssertEqual(try Rules.decode(Rules.encode(base)), base)
        for c in f["cases"]?.array ?? [] {
            let set: RuleSet
            if let r = c["rules"], !r.isNull { set = try Rules.fromJSON(r) } else { set = base }
            let got = Rules.route(set, variables: strMap(c["variables"]), activeProfileId: c["activeProfileId"]?.string)
            let id = c["id"]!.string!
            XCTAssertEqual(got.profileIds, (c["expectProfiles"]?.array ?? []).compactMap { $0.string }, id)
            XCTAssertEqual(got.ruleId, c["expectRule"]?.string, id)
        }
        let byId = Dictionary(uniqueKeysWithValues: base.rules.map { ($0.id, $0) })
        for e in f["errors"]?.array ?? [] {
            XCTAssertEqual(Rules.error(byId[e["id"]!.string!]!), e["error"]?.string, e["id"]!.string!)
        }
        for e in f["extraErrors"]?.array ?? [] {
            let rule = try Rules.fromJSON(.object([JSONMember("rules", .array([e["rule"]!]))])).rules[0]
            XCTAssertEqual(Rules.error(rule), e["error"]?.string)
        }
    }

    func testResultText() throws {
        let f = try fixture("result_text_vectors.json")
        for c in f["cases"]?.array ?? [] {
            let got = ResultText.render(c["template"]?.string, status: c["status"]?.int, message: c["message"]?.string,
                                        uid: c["uid"]!.string!, profile: c["profile"]!.string!)
            XCTAssertEqual(got, c["expect"]?.string, c["template"]?.string ?? "nil")
        }
    }
}
