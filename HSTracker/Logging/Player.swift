/*
 * This file is part of the HSTracker package.
 * (c) Benjamin Michotte <bmichotte@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 *
 * Created on 17/02/16.
 */

import Foundation

class DynamicEntity {
    var cardId: String
    var stolen, hidden, created, isInHand, discarded: Bool
    var cardMark: CardMark
    var entity: Entity?

    init(cardId: String, hidden: Bool = false, created: Bool = false,
         cardMark: CardMark = .none, discarded: Bool = false,
         stolen: Bool = false, isInHand: Bool = false, entity: Entity? = nil) {
        self.cardId = cardId
        self.hidden = hidden
        self.created = created
        self.discarded = discarded
        self.cardMark = cardMark
        self.stolen = stolen
        self.isInHand = isInHand
        self.entity = entity
    }
}

extension DynamicEntity: Hashable {
    func hash(into hasher: inout Hasher) {
        cardId.hash(into: &hasher)
        hidden.hash(into: &hasher)
        created.hash(into: &hasher)
        discarded.hash(into: &hasher)
        stolen.hash(into: &hasher)
        cardMark.hash(into: &hasher)
        isInHand.hash(into: &hasher)
    }

    static func == (lhs: DynamicEntity, rhs: DynamicEntity) -> Bool {
        return lhs.cardId == rhs.cardId &&
            lhs.hidden == rhs.hidden &&
            lhs.created == rhs.created &&
            lhs.discarded == rhs.discarded &&
            lhs.cardMark == rhs.cardMark &&
            lhs.stolen == rhs.stolen &&
            lhs.isInHand == rhs.isInHand
    }
}

class DeckState {
    fileprivate(set) var remainingInDeck: [Card]
    fileprivate(set) var removedFromDeck: [Card]

    init(remainingInDeck: [Card], removedFromDeck: [Card]) {
        self.removedFromDeck = removedFromDeck
        self.remainingInDeck = remainingInDeck
    }
}

class PredictedCard {
    var cardId: String
    var turn: Int
    var isCreated: Bool

    init(cardId: String, turn: Int, isCreated: Bool = false) {
        self.cardId = cardId
        self.turn = turn
        self.isCreated = isCreated
    }
}

extension PredictedCard: Hashable {
    func hash(into hasher: inout Hasher) {
        cardId.hash(into: &hasher)
        turn.hash(into: &hasher)
    }

    static func == (lhs: PredictedCard, rhs: PredictedCard) -> Bool {
        return lhs.cardId == rhs.cardId && lhs.turn == rhs.turn
    }
}

final class Player {
    var playerClass: CardClass?
    var playerClassId: String?
    var isLocalPlayer: Bool
    var id = -1
    var fatigue = 0
    var heroPowerCount = 0
    var lastDiedMinionCardId: String?
    fileprivate(set) var spellsPlayedCount = 0
    fileprivate(set) var cardsPlayedThisTurn: [String] = []
    var isPlayingWhizbang: Bool = false
    fileprivate(set) var deathrattlesPlayedCount = 0
	private unowned(unsafe) let game: Game
    var lastDrawnCardId: String?
    var libramReductionCount: Int = 0
    var abyssalCurseCount: Int = 0

    var hasCoin: Bool {
        return hand.any { $0.cardId == CardIds.NonCollectible.Neutral.TheCoinBasic }
    }

    var handCount: Int {
        return hand.filter({ $0.isControlled(by: self.id) }).count
    }

    /** Number of cards still in the deck */
    var deckCount: Int {
        return deck.filter({ $0.isControlled(by: self.id) }).count
    }

    var playerEntities: [Entity] {
        return game.entities.values.filter({
            return !$0.info.hasOutstandingTagChanges && $0.isControlled(by: self.id)
        })
    }

    var revealedEntities: [Entity] {
        return game.entities.values
            .filter({
                return !$0.info.hasOutstandingTagChanges
                    && ($0.isControlled(by: self.id) || $0.info.originalController == self.id)
            }).filter({ $0.hasCardId })
    }

    var hand: [Entity] { return playerEntities.filter({ $0.isInHand }) }
    var board: [Entity] { return playerEntities.filter({ $0.isInPlay }) }
    var deck: [Entity] { return playerEntities.filter({ $0.isInDeck }) }
    var graveyard: [Entity] { return playerEntities.filter({ $0.isInGraveyard }) }
    var secrets: [Entity] { return playerEntities.filter({ $0.isInSecret && $0.isSecret }) }
    var quests: [Entity] { return playerEntities.filter({ $0.isInSecret && $0.isQuest }) }
    var questRewards: [Entity] { return board.filter({ $0.isBgsQuestReward }) }
    var setAside: [Entity] { return playerEntities.filter({ $0.isInSetAside }) }
    var entity: Entity? {
        return game.entities.values.filter({ $0[.player_id] == self.id }).first
    }

    fileprivate(set) lazy var inDeckPredictions = [PredictedCard]()

    var name: String?
    var tracker: Tracker?
    var drawnCardsMatchDeck = true

	init(local: Bool, game: Game) {
		self.game = game
        isLocalPlayer = local
        reset()
    }

    func reset() {
        id = -1
        name = ""
        playerClass = nil
        fatigue = 0
        spellsPlayedCount = 0
        deathrattlesPlayedCount = 0
        heroPowerCount = 0

        inDeckPredictions.removeAll()
        
        lastDrawnCardId = nil
        libramReductionCount = 0
        abyssalCurseCount = 0
    }
    
    var currentMana: Int {
        return self.maxMana - (entity?[.resources_used] ?? 0)
    }
    
    var maxMana: Int {
        return (entity?[.resources] ?? 0) + (entity?[.temp_resources] ?? 0)
    }

    var displayRevealedCards: [Card] {
        return revealedEntities.filter({ x in
            return !x.info.created
                && x.isPlayableCard
                && (!x.isInDeck || (x.info.stolen && x.info.originalController == self.id))
        })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: e.cardId,
                    hidden: (e.isInHand || e.isInDeck),
                    created: e.info.created ||
                        (e.info.stolen && e.info.originalController != self.id),
                    discarded: e.info.discarded && Settings.highlightDiscarded)
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.jousted = g.key.hidden
                    card.isCreated = g.key.created
                    card.wasDiscarded = g.key.discarded
                    return card
                } else {
                    return nil
                }
            }
            .sortCardList()
    }

    func getPredictedCardsInDeck(hidden: Bool) -> [Card] {
        return inDeckPredictions.compactMap { g -> Card? in
            if let card = Cards.by(cardId: g.cardId) {
                if hidden {
                    card.jousted = true
                }
                if g.isCreated {
                    card.isCreated = true
                    card.count = 1
                }
                return card
            } else {
                return nil
            }
        }
    }

    var knownCardsInDeck: [Card] {
        return deck.filter({ $0.hasCardId })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: e.cardId,
                    created: e.info.created || e.info.stolen)
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.isCreated = g.key.created
                    card.jousted = true
                    return card
                } else {
                    return nil
                }
            }
    }

    var revealedCards: [Card] {
        return revealedEntities.filter({ x in
            let created = x.info.created
            let type = (x.isMinion || x.isSpell || x.isWeapon || x.isHero)
            let zone = ((!x.isInDeck
                && (!x.info.stolen || x.info.originalController == self.id))
                || (x.info.stolen && x.info.originalController == self.id))

            return (!created || x.info.originalEntityWasCreated == false) && type && zone
        })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: e.cardId,
                    stolen: e.info.stolen && e.info.originalController != self.id,
                    entity: e)
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.isCreated = g.key.stolen
                    card.highlightInHand = g.value.any({
                        $0.isInHand && $0.entity!.isControlled(by: self.id)
                    })
                    return card
                } else {
                    return nil
                }
            }
    }

    var createdCardsInHand: [Card] {
        return hand.filter { ($0.info.created || $0.info.stolen) }
            .group { (e: Entity) in e.cardId }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key) {
                    card.count = g.value.count
                    card.isCreated = true
                    card.highlightInHand = true
                    return card
                } else {
                    return nil
                }
            }
    }

    func getHighlightedCardsInHand(cardsInDeck: [Card]) -> [Card] {
		
        guard let deck = game.currentDeck else { return [] }

        return deck.cards.filter({ (c) -> Bool in
            cardsInDeck.all({ $0.id != c.id }) && hand.any({ $0.cardId == c.id })
        })
            .compactMap {
                let card = $0.copy()
                card.count = 0
                card.highlightInHand = true
                return card
        }
    }

    var playerCardList: [Card] {
        let createdInHand = Settings.showPlayerGet ? createdCardsInHand : [Card]()
        if game.currentDeck == nil {
            return (revealedCards + createdInHand
                + knownCardsInDeck + getPredictedCardsInDeck(hidden: true)).sortCardList()
        }
        let deckState = getDeckState()
        let inDeck = deckState.remainingInDeck
        let notInDeck = deckState.removedFromDeck.filter({ x in inDeck.all({ x.id != $0.id }) })
        let predictedInDeck = getPredictedCardsInDeck(hidden: false).filter({ x in inDeck.all { c in x.id != c.id } })
        if !Settings.removeCardsFromDeck {
            return (inDeck + predictedInDeck + notInDeck + createdInHand).sortCardList()
        }
        if Settings.highlightCardsInHand {
            return (inDeck + predictedInDeck + getHighlightedCardsInHand(cardsInDeck: inDeck)
                + createdInHand).sortCardList()
        }
        return (inDeck + predictedInDeck + createdInHand).sortCardList()
    }

    var opponentCardList: [Card] {
        let revealed = revealedEntities.filter({ (e: Entity) in
            !(e.info.guessedCardState == GuessedCardState.none && e.info.hidden && (e.isInDeck || e.isInHand))
            && (e.isPlayableCard || !e.has(tag: .cardtype))
                && (e[.creator] == 1
                    || ((!e.info.created || (Settings.showOpponentCreated
                        && (e.info.createdInDeck || e.info.createdInHand)))
                    && e.info.originalController == self.id)
                        || e.isInHand || e.isInDeck)
                && !CardIds.hiddenCardidPrefixes.any({ y in e.cardId.starts(with: y) })
                && !entityIsRemovedFromGamePassive(entity: e)
                && !(e.info.created && e.isInSetAside && e.info.guessedCardState != GuessedCardState.guessed)
        })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: e.info.wasTransformed ? e.info.originalCardId ?? e.cardId : e.cardId,
                              hidden: (e.isInHand || e.isInDeck || (e.isInSetAside && e.info.guessedCardState == GuessedCardState.guessed)) && e.isControlled(by: self.id),
                    created: e.info.created ||
                        (e.info.stolen && e.info.originalController != self.id),
                    discarded: e.info.discarded && Settings.highlightDiscarded
                )
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.jousted = g.key.hidden
                    card.isCreated = g.key.created
                    card.wasDiscarded = g.key.discarded
                    return card
                } else {
                    return nil
                }
            }

        let inDeck = getPredictedCardsInDeck(hidden: true)

        return (revealed + inDeck).sortCardList()
    }

    private func entityIsRemovedFromGamePassive(entity: Entity) -> Bool {
        return entity.has(tag: GameTag.dungeon_passive_buff) && entity[GameTag.zone] == Zone.removedfromgame.rawValue
    }
    
    fileprivate func getDeckState() -> DeckState {
        let createdCardsInDeck: [Card] = deck.filter({
            $0.hasCardId && ($0.info.created || $0.info.stolen)
        })
            .map({ (e: Entity) -> (DynamicEntity) in
                DynamicEntity(cardId: e.cardId,
                    created: e.info.created || e.info.stolen,
                    discarded: e.info.discarded
                )
            })
            .group { (d: DynamicEntity) in d }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key.cardId) {
                    card.count = g.value.count
                    card.isCreated = g.key.created
                    card.highlightInHand = hand.any({ $0.cardId == g.key.cardId })
                    return card
                } else {
                    return nil
                }
            }

        var originalCardsInDeck: [String] = []
        if let deck = game.currentDeck {
            originalCardsInDeck = deck.cards.flatMap {
                Array(repeating: $0.id, count: $0.count)
                }
                .map({ $0 })
        }

        let revealedNotInDeck = revealedEntities.filter {
            (!$0.info.created || $0.info.originalEntityWasCreated == false)
                && $0.isPlayableCard
                && (!$0.isInDeck || $0.info.stolen)
                && $0.info.originalController == self.id
                && !($0.info.hidden && ($0.isInDeck || $0.isInHand))
        }

        var removedFromDeck = [String]()
        revealedNotInDeck.forEach({
            originalCardsInDeck.remove($0.cardId)
            if !$0.info.stolen || $0.info.originalController == self.id {
                removedFromDeck.append($0.cardId)
            }
        })

        let cardsInDeck: [Card] = createdCardsInDeck + (originalCardsInDeck
            .group { (c: String) in c }
            .compactMap { g -> Card? in
                if let card = Cards.by(cardId: g.key) {
                    card.count = g.value.count
                    if hand.any({ $0.cardId == g.key }) {
                        card.highlightInHand = true
                    }
                    return card
                } else {
                    return nil
                }
            })

        let cardsNotInDeck = removedFromDeck.group { (c: String) in c }
            .compactMap({ g -> Card? in
                if let card = Cards.by(cardId: g.key) {
                    card.count = 0
                    if hand.any({ e in e.cardId == g.key }) {
                        card.highlightInHand = true
                    }
                    return card
                } else {
                    return nil
                }
            })

        return DeckState(remainingInDeck: cardsInDeck, removedFromDeck: cardsNotInDeck)
    }

    fileprivate var debugName: String {
        return isLocalPlayer ? "Player" : "Opponent"
    }

    func createInDeck(entity: Entity, turn: Int) {
        if entity.info.discarded {
            entity.info.discarded = false
            entity.info.created = false
        } else {
            entity.info.created = entity.info.created || turn > 1
        }
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func createInHand(entity: Entity, turn: Int) {
        entity.info.created = true
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }
    
    func createInSetAside(entity: Entity, turn: Int) {
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }
    
    func handToDeck(entity: Entity, turn: Int) {
        entity.info.turn = turn
        entity.info.returned = true
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func boardToDeck(entity: Entity, turn: Int) {
        entity.info.turn = turn
        entity.info.returned = true
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func play(entity: Entity, turn: Int) {
        if !isLocalPlayer {
            updateKnownEntitesInDeck(cardId: entity.cardId, turn: turn)
        }

        if let cardType = CardType(rawValue: entity[.cardtype]) {
            switch cardType {
            case .token: entity.info.created = true
            case .spell: spellsPlayedCount += 1
            default: break
            }
        }
        entity.info.hidden = false
        entity.info.turn = turn
        cardsPlayedThisTurn.append(entity.cardId)
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func handDiscard(entity: Entity, turn: Int) {
        if !isLocalPlayer {
            updateKnownEntitesInDeck(cardId: entity.cardId, turn: entity.info.turn)
        }
        entity.info.turn = turn
        entity.info.discarded = true
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func secretPlayedFromDeck(entity: Entity, turn: Int) {
        updateKnownEntitesInDeck(cardId: entity.cardId)
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func secretPlayedFromHand(entity: Entity, turn: Int) {
        entity.info.turn = turn
        spellsPlayedCount += 1
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func questPlayedFromHand(entity: Entity, turn: Int) {
        entity.info.turn = turn
        spellsPlayedCount += 1
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func mulligan(entity: Entity) {
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func draw(entity: Entity, turn: Int) {
        if isLocalPlayer {
            updateKnownEntitesInDeck(cardId: entity.cardId)
        } else {
            if game.opponentEntity?[.mulligan_state] == Mulligan.dealing.rawValue {
                entity.info.mulliganed = true
            } else {
                entity.info.hidden = true
            }
        }
        entity.info.turn = turn
        lastDrawnCardId = entity.cardId
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func removeFromDeck(entity: Entity, turn: Int) {
        // Do not check for KnownCardIds here, this is how jousted cards get removed from the deck
        entity.info.turn = turn
        entity.info.discarded = true
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func removeFromPlay(entity: Entity, turn: Int) {
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func deckDiscard(entity: Entity, turn: Int) {
        updateKnownEntitesInDeck(cardId: entity.cardId)
        entity.info.turn = turn
        entity.info.discarded = true
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }
    
    func onTurnStart() {
        cardsPlayedThisTurn.removeAll()
    }

    func deckToPlay(entity: Entity, turn: Int) {
        updateKnownEntitesInDeck(cardId: entity.cardId)
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func playToGraveyard(entity: Entity, cardId: String?, turn: Int) {
        entity.info.turn = turn
        if entity.isMinion && entity.has(tag: .deathrattle) {
            deathrattlesPlayedCount += 1
        }
        
        if entity.isMinion {
            lastDiedMinionCardId = cardId
        }
        
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func joustReveal(entity: Entity, turn: Int) {
        entity.info.turn = turn
        if let card = inDeckPredictions.first(where: { $0.cardId == entity.cardId }) {
            card.turn = turn
        } else {
            inDeckPredictions.append(PredictedCard(cardId: entity.cardId, turn: turn))
        }
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func createInPlay(entity: Entity, turn: Int) {
        entity.info.created = true
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func createInSecret(entity: Entity, turn: Int) {
        entity.info.created = true
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func stolenByOpponent(entity: Entity, turn: Int) {
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func stolenFromOpponent(entity: Entity, turn: Int) {
        entity.info.turn = turn
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func boardToHand(entity: Entity, turn: Int) {
        entity.info.turn = turn
        entity.info.returned = true
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }

    func secretTriggered(entity: Entity, turn: Int) {
        entity.info.turn = turn
        game.secretsManager?.secretTriggered(entity: entity)
        if Settings.fullGameLog {
            logger.info("\(debugName) \(#function) \(entity)")
        }
    }
    
    func heroPower(turn: Int) {
        heroPowerCount += 1
    }

    private func updateKnownEntitesInDeck(cardId: String?, turn: Int = Int.max) {
        if let card = inDeckPredictions.first(where: { $0.cardId == cardId && turn >= $0.turn }) {
            inDeckPredictions.remove(card)
        }
    }
    
    func predictUniqueCardInDeck(cardId: String, isCreated: Bool) {
        if inDeckPredictions.all({ x in x.cardId != cardId }) {
            inDeckPredictions.append(PredictedCard(cardId: cardId, turn: 0, isCreated: isCreated))
        }
    }
    
    func updateLibramReduction(change: Int) {
        libramReductionCount += change
    }
    
    func updateAbyssalCurse(value: Int) {
        abyssalCurseCount = value > 0 ? value : abyssalCurseCount + 1
    }
    
    func shuffleDeck() {
        for card in deck {
            card.info.deckIndex = 0
        }
    }
}
