/*
* This file is part of the HSTracker package.
* (c) Benjamin Michotte <bmichotte@gmail.com>
*
* For the full copyright and license information, please view the LICENSE
* file that was distributed with this source code.
*
* Created on 13/02/16.
*/

import Foundation

final class LogReaderManager {
	
    // lower update times result in faster operation but higher CPU usage
	static let updateDelay: TimeInterval = 0.05
	
    let powerGameStateParser: LogEventParser
    let rachelleHandler = RachelleHandler()
	let arenaHandler: LogEventParser
	let loadingScreenHandler: LogEventParser
    let fullscreenFXHandler: LogEventParser

    private let powerLog: LogReader
    private let rachelle: LogReader
    private let arena: LogReader
    private let loadingScreen: LogReader
    private let decksReader = DecksReader()
    private let fullscreen: LogReader

    private var readers: [LogReader] {
        return [powerLog, rachelle, arena, loadingScreen, fullscreen]
    }
    
    public static let dateStringFormatter: LogDateFormatter = {
        let formatter = LogDateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    public static let iso8601StringFormatter: LogDateFormatter = {
        let formatter = LogDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()
    
    public static let fullDateStringFormatter: LogDateFormatter = {
        let formatter = LogDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return formatter
    }()
	
    public static let timeZone = TimeZone.current
    public static let calendar = Calendar.current

    var running = false
    var stopped = false
    private var queue: DispatchQueue?
    private let coreManager: CoreManager
    
	init(logPath: String, coreManager: CoreManager) {
        self.coreManager = coreManager
		loadingScreenHandler = LoadingScreenHandler(with: coreManager)
		powerGameStateParser = PowerGameStateParser(with: coreManager.game)
		arenaHandler = ArenaHandler(with: coreManager)
        fullscreenFXHandler = FullScreenFxHandler(coreManager: coreManager)
		
        let plReader = LogReaderInfo(name: .power,
                                     startsWithFilters: ["PowerTaskList.DebugPrintPower", "GameState."],
                                     containsFilters: ["Begin Spectating", "Start Spectator",
                                                       "End Spectator"])
        powerLog = LogReader(info: plReader, logPath: logPath)

        rachelle = LogReader(info: LogReaderInfo(name: .rachelle), logPath: logPath)
        arena = LogReader(info: LogReaderInfo(name: .arena), logPath: logPath)
        loadingScreen = LogReader(info: LogReaderInfo(name: .loadingScreen,
                                                      startsWithFilters: ["LoadingScreen.OnSceneLoaded", "Gameplay"]),
                                  logPath: logPath)
        fullscreen = LogReader(info: LogReaderInfo(name: .fullScreenFX), logPath: logPath)
    }

    func start() {
        guard !running else {
            logger.error("LogReaderManager is already running")
            return
        }
        logger.info("LogReaderManager is starting")
        
        queue = DispatchQueue(label: "net.hearthsim.hstracker.logReaderManager", attributes: [])
        
        guard let queue = queue else {
            logger.error("LogReaderManager can not create queue")
            return
        }
        self.running = true
        queue.async {
            self.startLogReaders()
        }
    }
    
    private func startLogReaders() {
        stopped = false
        running = true
        let entryPoint = self.entryPoint()
        for reader in readers {
            reader.start(manager: self, entryPoint: entryPoint)
        }
        decksReader.start()
        
        while !stopped {
            autoreleasepool {
                var processMap = [LogDate: [LogLine]]()

                for reader in readers {
                    let loglines = reader.collect()
                    for line in loglines {
                        var lineList = processMap[line.time] ?? [LogLine]()
                        lineList.append(line)
                        processMap[line.time] = lineList
                    }
                    
                }
                
                let keys = processMap.keys.sorted()
                for time in keys {
                    if let lineList = processMap[time] {
                        if stopped {
                            break
                        }
                        for line in lineList {
                            if stopped {
                                break
                            }
                            processLine(line: line)
                        }
                    }
                }
                processMap.removeAll()
            }
            Thread.sleep(forTimeInterval: LogReaderManager.updateDelay)
        }
        running = false
    }

	func stop(eraseLogFile: Bool) {
        logger.info("Stopping all trackers")
        stopped = true
        running = false
        for reader in readers {
			reader.stop(eraseLogFile: eraseLogFile)
        }
        decksReader.stop()
    }

	func restart(eraseLogFile: Bool = false) {
        logger.info("LogReaderManager is restarting")
		stop(eraseLogFile: eraseLogFile)
        start()
    }

    private func entryPoint() -> LogDate {
        let powerEntry = powerLog.findEntryPoint(choices:
            ["tag=STATE value=COMPLETE", "End Spectator"])
        let loadingScreenEntry = loadingScreen.findEntryPoint(choice: "Gameplay.Start")

        let pe = LogReaderManager.iso8601StringFormatter.string(from: powerEntry)
        let lse = LogReaderManager.iso8601StringFormatter.string(from: loadingScreenEntry)
        logger.verbose("powerEntry : \(pe) / loadingScreenEntry : \(lse)")
        
        return powerEntry > loadingScreenEntry ? powerEntry : loadingScreenEntry
	}
	
	private func processLine(line: LogLine) {
        switch line.namespace {
        case .power:
            if line.content.hasPrefix("GameState.") {
                coreManager.game.add(powerLog: line)
            } else {
                self.powerGameStateParser.handle(logLine: line)
            }
        case .rachelle: self.rachelleHandler.handle(logLine: line)
        case .arena: self.arenaHandler.handle(logLine: line)
        case .loadingScreen: self.loadingScreenHandler.handle(logLine: line)
        case .fullScreenFX: self.fullscreenFXHandler.handle(logLine: line)
        default: break
		}
	}
}
