import SQLite
import XCTest

struct Planet: SQLiteTable {
    var id: Int?
    var name: String
    var galaxyID: Int
    init(id: Int? = nil, name: String, galaxyID: Int) {
        self.id = id
        self.name = name
        self.galaxyID = galaxyID
    }
}
struct Galaxy: SQLiteTable {
    var id: Int?
    var name: String
    init(id: Int? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

class SQLiteTests: XCTestCase {
    func testSQLQuery() throws {     
        let conn = try SQLiteConnection.makeTest()
        
        _ = try conn.query("PRAGMA foreign_keys = ON;")
            .wait()
        
        try conn.drop(table: Planet.self)
            .ifExists()
            .run().wait()
        try conn.drop(table: Galaxy.self)
            .ifExists()
            .run().wait()
        
        try conn.create(table: Galaxy.self)
            .column(for: \Galaxy.id, .integer, .primaryKey(), .notNull)
            .column(for: \Galaxy.name)
            .run().wait()
        try conn.create(table: Planet.self)
            .column(for: \Planet.id, .integer, .primaryKey(), .notNull)
            .column(for: \Planet.galaxyID, .integer, .notNull, .foreignKey(to: \Galaxy.id))
            .run().wait()

        try conn.alter(table: Planet.self)
            .addColumn(for: \Planet.name, .text, .notNull, .default(.literal("Unamed Planet")))
            .run().wait()

        try conn.insert(into: Galaxy.self)
            .value(Galaxy(name: "Milky Way"))
            .run().wait()

        let galaxyID = conn.lastAutoincrementID!
        
        try conn.insert(into: Planet.self)
            .value(Planet(name: "Earth", galaxyID: galaxyID))
            .run().wait()
        
        try conn.insert(into: Planet.self)
            .values([
                Planet(name: "Mercury", galaxyID: galaxyID),
                Planet(name: "Venus", galaxyID: galaxyID),
                Planet(name: "Mars", galaxyID: galaxyID),
                Planet(name: "Jpuiter", galaxyID: galaxyID),
                Planet(name: "Pluto", galaxyID: galaxyID)
            ])
            .run().wait()
        
        try conn.update(Planet.self)
            .where(\Planet.name == "Jpuiter")
            .set(["name": "Jupiter"])
            .run().wait()
        
        let selectA = try conn.select().all()
            .from(Planet.self)
            .where(or: \Planet.name == "Mars", \Planet.name == "Venus", \Planet.name == "Earth")
            .run(decoding: Planet.self).wait()
        print(selectA)

        try conn.delete(from: Planet.self).where(\Planet.name == "Pluto")
            .run().wait()

        let selectB = try conn.select().all().from(Planet.self)
            .run(decoding: Planet.self).wait()
        print(selectB)

        let selectC = try conn.select().all()
            .from(Planet.self)
            .join(Galaxy.self, on: \Planet.galaxyID == \Galaxy.id)
            .run { try ($0.decode(Planet.self), $0.decode(Galaxy.self)) }
            .wait()
        print(selectC)
    }
    
    func testTables() throws {
        let database = try SQLiteConnection.makeTest()
        _ = try database.query("DROP TABLE IF EXISTS foo").wait()
        _ = try database.query("CREATE TABLE foo (bar INT(4), baz VARCHAR(16), biz FLOAT)").wait()
        _ = try database.query("INSERT INTO foo VALUES (42, 'Life', 0.44)").wait()
        _ = try database.query("INSERT INTO foo VALUES (1337, 'Elite', 209.234)").wait()
        _ = try database.query("INSERT INTO foo VALUES (9, NULL, 34.567)").wait()
        
        if let resultBar = try database.query("SELECT * FROM foo WHERE bar = 42").wait().first {
            XCTAssertEqual(resultBar.firstValue(forColumn: "bar"), .integer(42))
            XCTAssertEqual(resultBar.firstValue(forColumn: "baz"), .text("Life"))
            XCTAssertEqual(resultBar.firstValue(forColumn: "biz"), .float(0.44))
        } else {
            XCTFail("Could not get bar result")
        }
        
        
        if let resultBaz = try database.query("SELECT * FROM foo where baz = 'Elite'").wait().first {
            XCTAssertEqual(resultBaz.firstValue(forColumn: "bar"), .integer(1337))
            XCTAssertEqual(resultBaz.firstValue(forColumn: "baz"), .text("Elite"))
        } else {
            XCTFail("Could not get baz result")
        }
        
        if let resultBaz = try database.query("SELECT * FROM foo where bar = 9").wait().first {
            XCTAssertEqual(resultBaz.firstValue(forColumn: "bar"), .integer(9))
            XCTAssertEqual(resultBaz.firstValue(forColumn: "baz"), .null)
        } else {
            XCTFail("Could not get null result")
        }
    }
    
    func testUnicode() throws {
        let database = try SQLiteConnection.makeTest()
        /// This string includes characters from most Unicode categories
        /// such as Latin, Latin-Extended-A/B, Cyrrilic, Greek etc.
        let unicode = "®¿ÐØ×ĞƋƢǂǊǕǮȐȘȢȱȵẀˍΔῴЖ♆"
        _ = try database.query("DROP TABLE IF EXISTS `foo`").wait()
        _ = try database.query("CREATE TABLE `foo` (bar TEXT)").wait()
        
        _ = try database.query("INSERT INTO `foo` VALUES(?)", [unicode.convertToSQLiteData()]).wait()
        let selectAllResults = try database.query("SELECT * FROM `foo`").wait().first
        XCTAssertNotNil(selectAllResults)
        XCTAssertEqual(selectAllResults!.firstValue(forColumn: "bar"), .text(unicode))
        
        let selectWhereResults = try database.query("SELECT * FROM `foo` WHERE bar = '\(unicode)'").wait().first
        XCTAssertNotNil(selectWhereResults)
        XCTAssertEqual(selectWhereResults!.firstValue(forColumn: "bar"), .text(unicode))
    }
    
    func testBigInts() throws {
        let database = try SQLiteConnection.makeTest()
        let max = Int.max
        
        _ = try database.query("DROP TABLE IF EXISTS foo").wait()
        _ = try database.query("CREATE TABLE foo (max INT)").wait()
        _ = try database.query("INSERT INTO foo VALUES (?)", [max.convertToSQLiteData()]).wait()
        
        if let result = try! database.query("SELECT * FROM foo").wait().first {
            XCTAssertEqual(result.firstValue(forColumn: "max"), .integer(max))
        }
    }
    
    func testBlob() throws {
        let database = try SQLiteConnection.makeTest()
        let data = Data(bytes: [0, 1, 2])
        
        _ = try database.query("DROP TABLE IF EXISTS `foo`").wait()
        _ = try database.query("CREATE TABLE foo (bar BLOB(4))").wait()
        _ = try database.query("INSERT INTO foo VALUES (?)", [data.convertToSQLiteData()]).wait()
        
        if let result = try database.query("SELECT * FROM foo").wait().first {
            XCTAssertEqual(result.firstValue(forColumn: "bar"), .blob(data))
        } else {
            XCTFail()
        }
    }
    
    func testError() throws {
        let database = try SQLiteConnection.makeTest()
        do {
            _ = try database.query("asdf").wait()
            XCTFail("Should have errored")
        } catch let error as SQLiteError {
            print(error)
            XCTAssert(error.reason.contains("syntax error"))
        } catch {
            XCTFail("wrong error")
        }
    }
    
    // https://github.com/vapor/sqlite/issues/33
    func testDecodeSameColumnName() throws {
        let row: [SQLiteColumn: SQLiteData] = [
            SQLiteColumn(table: "foo", name: "id"): .text("foo"),
            SQLiteColumn(table: "bar", name: "id"): .text("bar"),
        ]
        struct User: Decodable {
            var id: String
        }
        try XCTAssertEqual(SQLiteRowDecoder().decode(User.self, from: row, table: "foo").id, "foo")
        try XCTAssertEqual(SQLiteRowDecoder().decode(User.self, from: row, table: "bar").id, "bar")
    }
    
    func testMultiThreading() throws {
        let db = try SQLiteDatabase(storage: .memory)
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let a = elg.next()
        let b = elg.next()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            let conn = try! db.newConnection(on: a).wait()
            for i in 0..<100 {
                print("a \(i)")
                let res = try! conn.query("SELECT (1 + 1) as a;").wait()
                print(res)
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            let conn = try! db.newConnection(on: b).wait()
            for i in 0..<100 {
                print("b \(i)")
                let res = try! conn.query("SELECT (1 + 1) as b;").wait()
                print(res)
            }
            group.leave()
        }
        group.wait()
    }
    
    static let allTests = [
        ("testTables", testTables),
        ("testUnicode", testUnicode),
        ("testBigInts", testBigInts),
        ("testBlob", testBlob),
        ("testError", testError),
        ("testDecodeSameColumnName", testDecodeSameColumnName)
    ]
}
