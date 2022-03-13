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
    
    static let endpoint = "https://raw.githubusercontent.com/iccub/brave-ios/development"
    
    private init(networkManager: NetworkManager = NetworkManager()) {
        self.networkManager = networkManager
        Preferences.Shields.useRegionAdBlock.observe(from: self)
    }
    
    /// Initialized with year 1970 to force adblock fetch at first launch.
    private(set) var lastFetchDate = Date(timeIntervalSince1970: 0)
    
    func startLoading() {
        let now = Date()
        let fetchInterval = AppConstants.buildChannel.isPublic ? 6.hours : 10.minutes
        
        if now.timeIntervalSince(lastFetchDate) >= fetchInterval {
            lastFetchDate = now
            
            self.downloadCosmeticSamples()
            self.downloadResourceSamples()
        }
    }
    
    private func downloadCosmeticSamples() {
        if !Preferences.Shields.useRegionAdBlock.value {
            log.debug("Regional adblocking disabled, aborting attempt to download regional resources")
            return
        }
        
        downloadResources(type: .cosmeticSample,
                          queueName: "Cosmetic Sample Queue").uponQueue(.main) {
            log.debug("Downloaded Cosmetic Samples")
            Preferences.Debug.lastRegionalAdblockUpdate.value = Date()
        }
    }
    
    private func downloadResourceSamples() {
        downloadResources(type: .resourceSample,
                          queueName: "Resource Sample Queue").uponQueue(.main) {
            log.debug("Downloaded Resource Samples")
            Preferences.Debug.lastGeneralAdblockUpdate.value = Date()
        }
    }
    
    private func downloadResources(type: CosmeticFilterType, queueName: String) -> Deferred<()> {
        let completion = Deferred<()>()

        let queue = DispatchQueue(label: queueName)
        let nm = networkManager
        let folderName = AdblockResourceDownloader.folderName
        
        // file name of which the file will be saved on disk
        let fileName = type.identifier
        
        let completedDownloads = type.associatedFiles.map { fileType -> Deferred<CosmeticFilterNetworkResource> in
            let fileExtension = fileType.rawValue
            let etagExtension = fileExtension + ".etag"
            
            guard let resourceName = type.resourceName(for: fileType),
                var url = URL(string: AdblockResourceDownloader.endpoint) else {
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
        let folderName = AdblockResourceDownloader.folderName
        
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
                resourceSetup.append(AdBlockStats.shared.setDataFile(data: $0.resource.data,
                                                                     id: $0.type.identifier))
            case .json:
                if compileJsonRules {
                    resourceSetup.append(compileContentBlocker(resources: resources, queue: queue))
                }
            case .tgz:
                break // TODO: Add downloadable httpse list
            }
        }
        all(resourceSetup).uponQueue(queue) { _ in completion.fill(()) }
        return completion
    }
}

extension CosmeticFiltersResourceDownloader: PreferencesObserver {
    func preferencesDidChange(for key: String) {
        let regionalAdblockPref = Preferences.Shields.useRegionAdBlock
        if key == regionalAdblockPref.key {
            regionalAdblockResourcesSetup()
        }
    }
}

extension CosmeticFiltersResourceDownloader {
    enum CosmeticFilterType {
        case cosmeticSample
        case resourceSample
        
        var identifier: String {
            switch self {
            case .cosmeticSample: return "cosmetic_sample"
            case .resourceSample: return "resource_sample"
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
