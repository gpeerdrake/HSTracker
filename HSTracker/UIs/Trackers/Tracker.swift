/*
 * This file is part of the HSTracker package.
 * (c) Benjamin Michotte <bmichotte@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 *
 * Created on 15/02/16.
 */

import Cocoa

class Tracker: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, CardCellHover {

    @IBOutlet var table: NSTableView?
    @IBOutlet var tableColumn: NSTableColumn?

    var gameEnded: Bool = false
    var heroCard: Card?
    var cards = [Card]()
    var player: Player?
    var playerType: PlayerType?
    
    override func windowDidLoad() {
        super.windowDidLoad()

        self.gameEnded = false

        var width: Double
        let settings = Settings.instance
        switch settings.cardSize {
        case .Small:
            width = KSmallFrameWidth

        case .Medium:
            width = KMediumFrameWidth

        default:
            width = KFrameWidth
        }

        self.window!.setFrame(NSRect(x: 0, y: 0, width: width, height: 200), display: true)
        self.window!.contentMinSize = NSSize(width: width, height: 200)
        self.window!.contentMaxSize = NSSize(width: width, height: Double(NSHeight(NSScreen.mainScreen()!.frame)))

        self.window!.opaque = false
        self.window!.hasShadow = false
        self.window!.backgroundColor = NSColor.clearColor()

        let locked = settings.windowsLocked
        if locked {
            self.window!.styleMask = NSBorderlessWindowMask;
        } else {
            self.window!.styleMask = NSTitledWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask | NSBorderlessWindowMask
        }
        self.window!.ignoresMouseEvents = locked
        self.window!.acceptsMouseMovedEvents = true

        if Hearthstone.instance.isHearthstoneRunning {
            self.window!.level = Int(CGWindowLevelForKey(CGWindowLevelKey.ScreenSaverWindowLevelKey))
        }
        self.table!.setDelegate(self)
        self.table!.setDataSource(self)
        self.table!.intercellSpacing = NSSize(width: 0, height: 0)

        self.table!.backgroundColor = NSColor.clearColor()
        self.table!.autoresizingMask = [NSAutoresizingMaskOptions.ViewWidthSizable, NSAutoresizingMaskOptions.ViewHeightSizable]

        self.tableColumn!.width = NSWidth(self.table!.bounds)
        self.tableColumn!.resizingMask = NSTableColumnResizingOptions.AutoresizingMask
        
        self.table!.reloadData()
    }

    // MARK: - NSTableViewDelegate / NSTableViewDataSource
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        var count = self.cards.count

        /*if ([Settings instance].handCountWindow == HandCountPosition_Tracker) {
        count += 1;
        }*/

        if let playerType = self.playerType where self.gameEnded && playerType == .Opponent {
            count += 1
        }

        return count
    }

    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let card = self.cards[row]
        let cell = CardCellView()
        cell.card = card
        cell.playerType = self.playerType
        cell.setDelegate(self)

        if card.hasChanged {
            card.hasChanged = false
            cell.flash()
        }
        return cell
        //}
        //else {
        //cell = CountTextCellView.new
        //cell.text = @count_text
        //}
    }

    func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        /*if (Configuration.hand_count_window == :tracker && row >= @playing_cards.count) {
        case Configuration.card_layout
        when :small
        ratio = TrackerLayout::KRowHeight / TrackerLayout::KSmallRowHeight
        when :medium
        ratio = TrackerLayout::KRowHeight / TrackerLayout::KMediumRowHeight
        else
        ratio = 1.0
        end
        50.0 / ratio
        }
        else {*/
        switch Settings.instance.cardSize {
        case .Small:
            return CGFloat(KSmallRowHeight)

        case .Medium:
            return CGFloat(KMediumRowHeight)

        default:
            return CGFloat(KRowHeight)
        }
        //}
    }

    func selectionShouldChangeInTableView(tableView: NSTableView) -> Bool {
        return false;
    }

    // MARK: - CardCellHover
    func hover(card: Card) {
        //DDLogInfo("hovering \(card)")
    }

    func out(card: Card) {
        //DDLogInfo(@"out \(card)")
    }

    // MARK: - Game
    func gameStart() {
        self.gameEnded = false
        self.cards.removeAll()
        self.table!.reloadData()
    }

    func gameEnd() {
        self.gameEnded = true
    }

    func update() {
        if let playerType = self.playerType {
            if let player = self.player {
                switch playerType {
                case .Player:
                    self.cards = player.displayCards()
                default:
                    self.cards = player.displayReveleadCards()
                }
                DDLogVerbose("cards for \(playerType) : \(self.cards)")
                self.table!.reloadData()
            }
        }
    }

}
