//
//  DataLoader.swift
//  DataLoader
//
//  Created by Luciano Almeida on 01/02/17.
//  Copyright © 2017 Luciano Almeida. All rights reserved.
//


open class DataLoader<K: Equatable&Hashable, V>: NSObject {
    public typealias Loader = (_ key: K ,_ resolve: @escaping (_ value: V?) -> Void, _ reject: @escaping (_ error: Error) -> Void)-> Void
    public typealias ResultCallBack = (_ value: V?, _ error: Error?) -> Void
    
    
    private var loader: Loader!
    private(set) var memoryCache: Cache<K,V> = Cache<K,V>()
    
    private var dispatchQueue: DispatchQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
    
    private var awaitingCallBacks: [K : [ResultCallBack]] = [:]
    private var inloadKeys: [K] = []
    
    public init(loader: @escaping Loader) {
        super.init()
        self.loader = loader
    }
    
    public convenience init(loader: @escaping Loader, cacheMaxAge: TimeInterval, allowsExpiration: Bool) {
        self.init(loader: loader, cacheMaxAge: cacheMaxAge)
        memoryCache.allowsExpiration = allowsExpiration
    }
    
    public convenience init(loader: @escaping Loader, allowsExpiration: Bool) {
        self.init(loader: loader)
        memoryCache.allowsExpiration = allowsExpiration
    }
    
    public convenience init(loader: @escaping Loader, cacheMaxAge: TimeInterval) {
        self.init(loader: loader)
        memoryCache.maxAge = cacheMaxAge
    }
    
    
    /**
    
     Load a value based on the the provided key. The loader is perfomed by the function passed on the contructor and the loaded value is based on the resolve function.
     
     - parameter key: The key for the data to be loaded.
     - parameter shouldCache: The values that indicates if loaded values should be cached.
     - parameter completion: The callback called after load finishes with a value or an error.
     - parameter value: The loaded value.
     - parameter error: Error that occurs in loading.
     
     */
    open func load(key: K, shouldCache: Bool = true, completion : @escaping ResultCallBack) {
        dispatchQueue.async {
            if self.memoryCache.contains(key: key) {
                completion(self.memoryCache.get(for: key), nil)
            }else {
                self.setWaitingCallBack(for: key, callback: completion)
                //In case the loader is already loading the key, just add to callback list and wait the loader finish.
                if !self.inloadKeys.contains(key) {
                    self.inloadKeys.append(key)
                    self.loader!(key ,{ (value) in
                        self.inloadKeys.remove(object: key)
                        if shouldCache {
                            if let value = value {
                                self.memoryCache.set(value: value, for: key)
                            }
                        }
                        self.performCallbacks(for: key, value: value, error: nil)
                    }) { (error) in
                        self.inloadKeys.remove(object: key)
                        self.performCallbacks(for: key, value: nil, error: error)
                    }
                }
                
            }
        }
    }
    
    private func setWaitingCallBack(for key: K,  callback : @escaping ResultCallBack) {
        if var cbs = awaitingCallBacks[key] {
            cbs.append(callback)
        }else {
            awaitingCallBacks.updateValue([callback], forKey: key)
        }
    }
    
    private func performCallbacks(for key: K, value: V?, error: Error?) {
        if let cbs = awaitingCallBacks[key] {
            cbs.forEach({ (cb) in
                cb(value, error)
            })
        }
        awaitingCallBacks.removeValue(forKey: key)
    }
    
    /**
     
     Load a value based on the the provided key. The loader is perfomed by the function passed on the contructor and the loaded value is based on the resolve function.
     
     - parameter keys: The keys for the data set to be loaded.
     - parameter shouldCache: The values that indicates if loaded values should be cached.
     - parameter completion: The callback called after load finishes with a value or an error.
     - parameter values: The loaded values.
     - parameter error: Error that occurs in loading.
     
     - Important:
        This method perform the loads in sequece, that means its a serial process and the loads are performed one afer another and not in paralell.
     
     */
    open func load(keys: [K], shouldCache: Bool = true, completion : @escaping (_ values: [V]?, _ error: Error?) -> Void) {
        let queue = Queue<K>(values: keys)
        var values : [V] = []
        dispatchQueue.async {
            var loadError: Error?
            let semaphore = DispatchSemaphore(value: 0)
            while let key = queue.dequeue(), loadError == nil  {
                self.load(key: key, shouldCache: shouldCache, completion: { (value, error) in
                    if let loadedValue = value {
                        values.append(loadedValue)
                    }else {
                        loadError = error
                    }
                    semaphore.signal()
                })
                semaphore.wait()
            }
            if values.count == keys.count {
                completion(values, nil)
            }else {
                completion(nil, loadError)
            }
        }

    }
    
    /**
     
     Removes a key from cache.
     
     - parameter key: The key to remove.

     
     */
    open func cacheRemove(key: K) {
        self.memoryCache.remove(key: key)
    }
    
    
    /**
     
     Removes keys from cache.
     
     - parameter keys: The keys to remove.
     
     */
    open func cacheRemove(keys: [K]) {
        keys.forEach({ self.memoryCache.remove(key: $0) })
    }
}
