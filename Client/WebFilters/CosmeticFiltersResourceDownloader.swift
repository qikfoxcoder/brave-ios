// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Shared
import BraveShared

private let log = Logger.browserLogger

private struct CosmeticFilterNetworkResource {
    let resource: CachedNetworkResource
    let fileType: FileType
    let type: CosmeticFiltersResourceDownloader.CosmeticFilterType
}

class CosmeticFiltersResourceDownloader {
    static let shared = CosmeticFiltersResourceDownloader()
    
    private let networkManager: NetworkManager
    
    static let folderName = "cmf-data"
    private let servicesKeyName = "SERVICES_KEY"
    private let servicesKeyHeaderValue = "BraveServiceKey"
    private var engine = AdblockRustEngine()
    
    static let endpoint = "https://raw.githubusercontent.com/iccub/brave-ios/development"
    
    private init(networkManager: NetworkManager = NetworkManager()) {
        self.networkManager = networkManager
    }
    
    /// Initialized with year 1970 to force adblock fetch at first launch.
    private(set) var lastFetchDate = Date(timeIntervalSince1970: 0)
    
    func startLoading() {
        let now = Date()
        let fetchInterval = AppConstants.buildChannel.isPublic ? 6.hours : 10.minutes
        
        if now.timeIntervalSince(lastFetchDate) >= fetchInterval {
            lastFetchDate = now
            
            // MUST re-create the engine otherwise we get insane load times when calling:
            // `engine_add_resources`
            // This is because `engine_add_resources` will ADD resources, and not delete old ones
            // Thus we get a huge amount of memory usage and slow down.
            engine = AdblockRustEngine()
            
            loadDownloadedFiles()
            downloadCosmeticSamples()
            downloadResourceSamples()
        }
    }
    
    func cssRules(for url: URL) -> String? {
        engine.cssRules(for: url)
    }
    
    private func loadDownloadedFiles() {
        let fm = FileManager.default
        guard let folderUrl = fm.getOrCreateFolder(name: CosmeticFiltersResourceDownloader.folderName) else {
            log.error("Could not get directory with .dat and .json files")
            return
        }
        
        let enumerator = fm.enumerator(at: folderUrl, includingPropertiesForKeys: nil)
        let filePaths = enumerator?.allObjects as? [URL]
        let datFileUrls = filePaths?.filter { $0.pathExtension == "dat" }
        let jsonFileUrls = filePaths?.filter { $0.pathExtension == "json" }
        
        datFileUrls?.forEach {
            let fileName = $0.deletingPathExtension().lastPathComponent
            if let data = fm.contents(atPath: $0.path) {
                setDataFile(data: data, id: fileName)
            }
        }
        
        jsonFileUrls?.forEach {
            let fileName = $0.deletingPathExtension().lastPathComponent
            if let data = fm.contents(atPath: $0.path) {
                setJSONFile(data: data, id: fileName)
            }
        }
    }
    
    private func downloadCosmeticSamples() {
        downloadResources(type: .cosmeticSample,
                          queueName: "CSS Queue").uponQueue(.main) {
            log.debug("Downloaded Cosmetic Filters CSS Samples")
            Preferences.Debug.lastCosmeticFiltersCSSUpdate.value = Date()
        }
    }
    
    private func downloadResourceSamples() {
        downloadResources(type: .resourceSample,
                          queueName: "Scriplets Queue").uponQueue(.main) {
            log.debug("Downloaded Cosmetic Filters Scriptlets Samples")
            Preferences.Debug.lastCosmeticFiltersScripletsUpdate.value = Date()
        }
    }
    
    private func downloadResources(type: CosmeticFilterType, queueName: String) -> Deferred<()> {
        let completion = Deferred<()>()

        let queue = DispatchQueue(label: queueName)
        let nm = networkManager
        let folderName = CosmeticFiltersResourceDownloader.folderName
        
        // file name of which the file will be saved on disk
        let fileName = type.identifier
        
        let completedDownloads = type.associatedFiles.map { fileType -> Deferred<CosmeticFilterNetworkResource> in
            let fileExtension = fileType.rawValue
            let etagExtension = fileExtension + ".etag"
            
            guard let resourceName = type.resourceName(for: fileType),
                var url = URL(string: CosmeticFiltersResourceDownloader.endpoint) else {
                return Deferred<CosmeticFilterNetworkResource>()
            }
            
            url.appendPathComponent(resourceName)
            url.appendPathExtension(fileExtension)
            
            var headers = [String: String]()
            if let servicesKeyValue = Bundle.main.getPlistString(for: servicesKeyName) {
                headers[servicesKeyHeaderValue] = servicesKeyValue
            }
            
            let etag = fileFromDocumentsAsString("\(fileName).\(etagExtension)", inFolder: folderName)
            let request =
            nm.downloadResource(with: url, resourceType: .cached(etag: etag),
                                checkLastServerSideModification: !AppConstants.buildChannel.isPublic,
                                customHeaders: headers)
                .mapQueue(queue) { resource in
                    CosmeticFilterNetworkResource(resource: resource, fileType: fileType, type: type)
                }
            
            return request
        }
        
        all(completedDownloads).uponQueue(queue) { resources in
            if self.writeFilesTodisk(resources: resources, name: fileName, queue: queue) {
                self.setUpFiles(resources: resources, compileJsonRules: false, queue: queue)
                    .uponQueue(queue) { completion.fill(()) }
            }
        }
        
        return completion
    }
    
    private func fileFromDocumentsAsString(_ name: String, inFolder folder: String) -> String? {
        guard let folderUrl = FileManager.default.getOrCreateFolder(name: folder) else {
            log.error("Failed to get folder: \(folder)")
            return nil
        }
        
        let fileUrl = folderUrl.appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: fileUrl.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func writeFilesTodisk(resources: [CosmeticFilterNetworkResource],
                                  name: String,
                                  queue: DispatchQueue) -> Bool {
        var fileSaveCompletions = [Bool]()
        let fm = FileManager.default
        let folderName = CosmeticFiltersResourceDownloader.folderName
        
        resources.forEach {
            let fileName = name + ".\($0.fileType.rawValue)"
            fileSaveCompletions.append(fm.writeToDiskInFolder($0.resource.data, fileName: fileName,
                                                              folderName: folderName))
            
            if let etag = $0.resource.etag, let data = etag.data(using: .utf8) {
                let etagFileName = fileName + ".etag"
                fileSaveCompletions.append(fm.writeToDiskInFolder(data, fileName: etagFileName,
                                                                  folderName: folderName))
            }
            
            if let lastModified = $0.resource.lastModifiedTimestamp,
                let data = String(lastModified).data(using: .utf8) {
                let lastModifiedFileName = fileName + ".lastmodified"
                fileSaveCompletions.append(fm.writeToDiskInFolder(data, fileName: lastModifiedFileName,
                        folderName: folderName))
            }
            
        }
        
        // Returning true if all file saves completed succesfully
        return !fileSaveCompletions.contains(false)
    }
    
    private func setUpFiles(resources: [CosmeticFilterNetworkResource], compileJsonRules: Bool, queue: DispatchQueue) -> Deferred<()> {
        let completion = Deferred<()>()
        var resourceSetup = [Deferred<()>]()
        
        resources.forEach {
            switch $0.fileType {
            case .dat:
                resourceSetup.append(setDataFile(data: $0.resource.data,
                                                 id: $0.type.identifier))
                break
            case .json:
                resourceSetup.append(setJSONFile(data: $0.resource.data,
                                                 id: $0.type.identifier))
                break
            case .tgz:
                break
            }
        }
        all(resourceSetup).uponQueue(queue) { _ in completion.fill(()) }
        return completion
    }
    
    @discardableResult
    private func setDataFile(data: Data, id: String) -> Deferred<()> {
        let completion = Deferred<()>()
        
        AdBlockStats.adblockSerialQueue.async { [weak self] in
            guard let self = self else { return }
            if self.engine.set(data: data) {
                log.debug("Cosmetic-Filters file with id: \(id) deserialized successfully")
                completion.fill(())
            } else {
                log.error("Failed to deserialize adblock list with id: \(id)")
            }
        }
        
        return completion
    }
    
    @discardableResult
    private func setJSONFile(data: Data, id: String) -> Deferred<()> {
        let completion = Deferred<()>()
        
        AdBlockStats.adblockSerialQueue.async { [weak self] in
            guard let self = self else { return }
            self.engine.set(json: data)
            log.debug("Cosmetic-Filters file with id: \(id) deserialized successfully")
            completion.fill(())
        }
        
        return completion
    }
}

extension CosmeticFiltersResourceDownloader {
    enum CosmeticFilterType {
        case cosmeticSample
        case resourceSample
        
        var identifier: String {
            switch self {
            case .cosmeticSample: return "cosmetic_sample"
            case .resourceSample: return "resources_sample"
            }
        }
        
        var associatedFiles: [FileType] {
            switch self {
            case .cosmeticSample: return [.dat]
            case .resourceSample: return [.json]
            }
        }
        
        func resourceName(for fileType: FileType) -> String? {
            identifier
        }
    }
}
