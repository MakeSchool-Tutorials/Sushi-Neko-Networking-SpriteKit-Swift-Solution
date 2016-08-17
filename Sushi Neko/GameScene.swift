//
//  GameScene.swift
//  Sushi Neko
//
//  Created by Martin Walsh on 05/04/2016.
//  Copyright (c) 2016 Make School. All rights reserved.
//

import SpriteKit
import Firebase
import FirebaseDatabase
import FBSDKCoreKit
import FBSDKShareKit
import FBSDKLoginKit

/* Tracking enum for use with character and sushi side */
enum Side {
    case left, right, none
}

/* Tracking enum for game state */
enum GameState {
    case loading, title, ready, playing, gameOver
}

/* Social profile structure */
struct Profile {
    var name = ""
    var imgURL = ""
    var facebookId = ""
    var score = 0
}

class GameScene: SKScene {
    
    /* Game objects */
    var character: Character!
    var sushiBasePiece: SushiPiece!
    var playButton: MSButtonNode!
    var healthBar: SKSpriteNode!
    var scoreLabel: SKLabelNode!
    var playerProfile = Profile()
    
    /* Sushi tower array */
    var sushiTower: [SushiPiece] = []
    
    /* Highscore custom dictionary */
    var scoreTower: [Int:Profile] = [:]
    
    /* Game management */
    var state: GameState = .loading {
        didSet {
            if state == .title {
                stackSushi()
            }
        }
    }
    
    var health: CGFloat = 1.0 {
        didSet {
            /* Cap Health */
            if health > 1.0 { health = 1.0 }
            
            /* Scale health bar between 0.0 -> 1.0 e.g 0 -> 100% */
            healthBar.xScale = health
        }
    }
    
    var score: Int = 0 {
        didSet {
            scoreLabel.text = String(score)
        }
    }
    
    /* Sushi piece creation counter */
    var sushiCounter = 0
    
    /* Firebase connection */
    var firebaseRef = FIRDatabase.database().reference(withPath: "/highscore")
    
    override func didMove(to view: SKView) {
        /* Setup your scene here */
        
        /* Connect game objects */
        character = childNode(withName: "character") as! Character
        sushiBasePiece = childNode(withName: "sushiBasePiece") as! SushiPiece
        
        /* UI game objects */
        playButton = childNode(withName: "playButton") as! MSButtonNode
        healthBar = childNode(withName: "healthBar") as! SKSpriteNode
        scoreLabel = childNode(withName: "scoreLabel") as! SKLabelNode
        
        /* Setup play button selection handler */
        playButton.selectedHandler = {
            [unowned self] in
            /* Start game */
            self.state = .ready
        }
        
        /* Setup chopstick connections */
        sushiBasePiece.connectChopsticks()
        
        /* Facebook authentication check */
        if (FBSDKAccessToken.current() == nil) {
            
            /* No access token, begin FB authentication process */
            FBSDKLoginManager().logIn(withReadPermissions: ["public_profile","email","user_friends"], from:self.view?.window?.rootViewController, handler: {
                (facebookResult, facebookError) -> Void in
                
                if facebookError != nil {
                    print("Facebook login failed. Error \(facebookError)")
                } else if facebookResult!.isCancelled {
                    print("Facebook login was cancelled.")
                } else {
                    let accessToken = FBSDKAccessToken.current().tokenString
                    
                    print(accessToken)
                }
            })
        }
        
        /* Facebook profile lookup */
        if (FBSDKAccessToken.current() != nil) {
            
            FBSDKGraphRequest(graphPath: "me", parameters: ["fields": "id, first_name"]).start(completionHandler: { (connection, result, error) -> Void in
                if (error == nil){
                
                    if let result = result as? NSDictionary {
                        /* Update player profile */
                        self.playerProfile.facebookId = result.value(forKey: "id") as! String
                        self.playerProfile.name = result.value(forKey: "first_name") as! String
                        self.playerProfile.imgURL = "https://graph.facebook.com/\(self.playerProfile.facebookId)/picture?type=small"
                        print(self.playerProfile)
                    }
                }
            })
        }
        
        firebaseRef.queryOrdered(byChild: "score").queryLimited(toLast: 5).observe(.value, with: { snapshot in
            
            /* Check snapshot has results */
            if snapshot.exists() {
                
                /* Loop through data entries */
                for child in snapshot.children {
                    
                    if let child = child as? FIRDataSnapshot {
                        /* Create new player profile */
                        var profile = Profile()
                    
                        /* Assign player name */
                        profile.name = child.key
                    
                        let value = child.value as? NSDictionary
                        
                        /* Assign profile data */
                        profile.imgURL = value?.object(forKey: "image") as! String
                        profile.facebookId = value?.object(forKey: "id") as! String
                        profile.score = value?.object(forKey: "score") as! Int
                    
                        /* Add new high score profile to score tower using score as index */
                        self.scoreTower[profile.score] = profile
                    }
                }
            }
            
            self.state = .title
            
        }) { (error) in
            print(error.localizedDescription)
        }
    }
    
    
    func stackSushi() {
        /* Seed the sushi tower */
        
        /* Manually stack the start of the tower */
        addTowerPiece(.none)
        addTowerPiece(.right)
        
        /* Randomize tower to just outside of the screen */
        addRandomPieces(10)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        /* Called when a touch begins */
        
        /* Game not ready to play */
        if state == .gameOver || state == .title { return }
        
        /* Game begins on first touch */
        if state == .ready {
            state = .playing
        }
        
        for touch in touches {
            
            /* Get touch position in scene */
            let location = touch.location(in: self)
            
            /* Was touch on left/right hand side of screen? */
            if location.x > size.width / 2 {
                character.side = .right
            } else {
                character.side = .left
            }
            
            /* Grab sushi piece on top of the base sushi piece, it will always be 'first' */
            let firstPiece: SushiPiece! = sushiTower.first
            
            /* Check character side against sushi piece side (this is our death collision check)*/
            if character.side == firstPiece.side {
                
                /* Drop all the sushi pieces down a place (visually) */
                for sushiPiece in sushiTower {
                    sushiPiece.run(SKAction.move(by: CGVector(dx: 0, dy: -55), duration: 0.10))
                }
                
                gameOver()
                
                /* No need to continue as player dead */
                return
            }
            
            /* Increment Health */
            health += 0.1
            
            /* Increment Score */
            score += 1
            
            /* Remove from sushi tower array */
            sushiTower.removeFirst()
            
            /* Animate the punched sushi piece */
            firstPiece.flip(character.side)
            
            /* Add a new sushi piece to the top of the sushi tower */
            addRandomPieces(1)
            
            /* Drop all the sushi pieces down one place */
            for node:SushiPiece in sushiTower {
                node.run(SKAction.move(by: CGVector(dx: 0, dy: -55), duration: 0.10))
                
                /* Reduce zPosition to stop zPosition climbing over UI */
                node.zPosition -= 1
            }
        }
    }
    
    func addTowerPiece(_ side: Side) {
        /* Add a new sushi piece to the sushi tower */
        
        /* Copy original sushi piece */
        let newPiece = sushiBasePiece.copy() as! SushiPiece
        newPiece.connectChopsticks()
        
        /* Access last piece properties */
        let lastPiece = sushiTower.last
        
        /* Add on top of last piece, default on first piece */
        let lastPosition = lastPiece?.position ?? sushiBasePiece.position
        newPiece.position = lastPosition + CGPoint(x: 0, y: 55)
        
        /* Incremenet Z to ensure it's on top of the last piece, default on first piece*/
        let lastZPosition = lastPiece?.zPosition ?? sushiBasePiece.zPosition
        newPiece.zPosition = lastZPosition + 1
        
        /* Set side */
        newPiece.side = side
        
        /* Add sushi to scene */
        addChild(newPiece)
        
        /* Add sushi piece to the sushi tower */
        sushiTower.append(newPiece)
        
        /* Sushi tracker */
        sushiCounter += 1
        
        /* Do we have a social score to add to the current sushi piece? */
        guard let profile = scoreTower[sushiCounter] else { return }
        
        /* Grab profile image */
        guard let imgURL = URL(string: profile.imgURL) else { return }
        
        /* Perform code block asynchronously in background queue */
        DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
            
            /* Perform image download task */
            guard let imgData = try? Data(contentsOf: imgURL) else { return }
            guard let img = UIImage(data: imgData) else { return }
            
            /* Perform code block asynchronously in main queue */
            DispatchQueue.main.async {
                
                /* Create texture from image */
                let imgTex = SKTexture(image: img)
                
                /* Create background border */
                let imgNodeBg = SKSpriteNode(color: UIColor.gray, size: CGSize(width: 52, height: 52))
                
                /* Add as child of sushi piece */
                newPiece.addChild(imgNodeBg)
                imgNodeBg.zPosition = newPiece.zPosition + 1
                
                /* Create a new sprite using profile texture, cap size */
                let imgNode = SKSpriteNode(texture: imgTex, size: CGSize(width: 50, height: 50))
                
                /* Add profile sprite as child of sushi piece */
                imgNodeBg.addChild(imgNode)
                imgNode.zPosition = imgNodeBg.zPosition + 1
            }
        }
    }
    
    func addRandomPieces(_ total: Int) {
        /* Add random sushi pieces to the sushi tower */
        
        for _ in 1...total {
            
            /* Need to access last piece properties */
            let lastPiece = sushiTower.last as SushiPiece!
            
            /* Need to ensure we don't create impossible sushi structures */
            if lastPiece!.side != Side.none {
                addTowerPiece(.none)
            } else {
                
                /* Random Number Generator */
                let rand = CGFloat.random(min: 0, max: 1.0)
                
                if rand < 0.45 {
                    /* 45% Chance of a left piece */
                    addTowerPiece(.left)
                } else if rand < 0.9 {
                    /* 45% Chance of a right piece */
                    addTowerPiece(.right)
                } else {
                    /* 10% Chance of an empty piece */
                    addTowerPiece(.none)
                }
            }
        }
    }
    
    func gameOver() {
        /* Game over! */
        
        state = .gameOver
        
        /* Turn all the sushi pieces red*/
        for node:SushiPiece in sushiTower {
            node.run(SKAction.colorize(with: UIColor.red, colorBlendFactor: 1.0, duration: 0.50))
        }
        
        /* Make the player turn red */
        character.run(SKAction.colorize(with: UIColor.red, colorBlendFactor: 1.0, duration: 0.50))
        /*
        /* Check for new high score and has a facebook user id */
        if score > playerProfile.score && !playerProfile.facebookId.isEmpty {
            
            /* Update profile score */
            playerProfile.score = score
            
            /* Build data structure to be saved to firebase */
            let saveProfile = [playerProfile.name :
                ["image" : playerProfile.imgURL,
                    "score" : playerProfile.score,
                    "id" : playerProfile.facebookId ]]
            
            /* Save to Firebase */
            firebaseRef.updateChildValues(saveProfile, withCompletionBlock: {
                (error:NSError?, ref:FIRDatabaseReference!) in
                if (error != nil) {
                    print("Data save failed: ",error)
                } else {
                    print("Data saved success")
                }
            })
            
        } */
        
        /* Change play button selection handler */
        playButton.selectedHandler = {
            
            /* Grab reference to our SpriteKit view */
            let skView  = self.view
            
            /* Load Game scene */
            let scene = GameScene(fileNamed:"GameScene")
            
            /* Ensure correct aspect mode */
            scene?.scaleMode = .aspectFill
            
            /* Restart GameScene */
            skView?.presentScene(scene)
        }
    }
    
    override func update(_ currentTime: TimeInterval) {
        /* Called before each frame is rendered */
        if state != .playing { return }
        
        /* Decrease Health */
        health -= 0.01
        
        /* Has the player ran out of health? */
        if health < 0 { gameOver() }
    }
    
}
