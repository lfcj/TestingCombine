import Combine
import Foundation
import XCTest

class LocalFileSystemLoader {
    typealias LoadResult = Result<Data?, Error>

    private let url: URL
    init(url: URL) {
        self.url = url
    }

    func load() async throws -> LoadResult {
        let task = Task {
            try Data(contentsOf: url)
        }
        do {
            let loadedData = try await task.value
            return .success(loadedData)
        } catch {
            return .failure(error)
        }
    }

    func getPublisher() -> AnyPublisher<Data, Error> {
        Deferred {
            Future { promise in
                Task {
                    do {
                        let loadedResult = try await self.load()
                        if let data = try loadedResult.get() {
                            promise(.success(data))
                        } else {
                            promise(.failure(NSError(domain: "Not found data", code: 0)))
                        }
                    } catch {
                        promise(.failure(error as NSError))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

}

final class CombineHelperTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: testSpecificStoreURL())
        FileManager.default.createFile(atPath: testSpecificStoreURL().path, contents: "Example data".data(using: .utf8)!)
    }

    func testPassing_localSavedLocallyIsUsedWhenAvailable() {
        let url = testSpecificStoreURL()
        let (publisher, _) = makeSUT(url: url)

        let expectedData = waitForPublication(on: publisher)
        XCTAssertEqual("Example data", String(data: expectedData ?? Data(), encoding: .utf8))
    }

    func testFailing_localSavedLocallyIsUsedWhenAvailable() async {
        let url = testSpecificStoreURL()
        let (publisher, _) = makeSUT(url: url)

        let expectedData = waitForPublication(on: publisher) ?? Data()
        XCTAssertEqual("Example data", String(data: expectedData, encoding: .utf8))
    }

    func waitForPublication(on publisher: AnyPublisher<Data, Error>) -> Data? {
        let exp = expectation(description: "Wait for publisher")
        var expectedData: Data?
        publisher.sink(
            receiveCompletion: { completion in
                exp.fulfill()
            },
            receiveValue: { receivedData in
                expectedData = receivedData
            }
        ).store(in: &cancellables)
        
        wait(for: [exp], timeout: 10)
        return expectedData
    }

    func makeSUT(url: URL) -> (AnyPublisher<Data, Error>, LocalFileSystemLoader) {
        let localCache = LocalFileSystemLoader(url: url)
        return (localCache.getPublisher(), localCache)
    }

    private func testSpecificStoreURL() -> URL {
        cachesDirectory().appendingPathComponent("\(type(of: self)).store ")
    }

    private func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }


}

