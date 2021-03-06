//
//  GameLayer.m
//  hashtag-warrior
//
//  Created by Nick James on 18/01/2013.
//  Copyright 2013 Ossum Games. All rights reserved.
//

#import "GameLayer.h"
#import "GameOverScene.h"

#import "AccelerometerSimulation.h"

// Define macros to convert from an iPhone ccp to iPad ccp.
// Note: Not much use when using the size from the director (e.g. [[CCDirector sharedDirector] winSize].width) as this
//       returns the size of the current device.
#define kXoffsetiPad        64
#define kYoffsetiPad        32

#define ADJUST_X(__x__)\
(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? (__x__ * 2) + kXoffsetiPad : __x__)

#define ADJUST_Y(__y__)\
(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? (__y__ * 2) + kYoffsetiPad : __y__)

#define ADJUST_CCP(__p__)\
(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? ccp( ADJUST_X(__p__.x), ADJUST_Y(__p__.y) ) : __p__)

@implementation GameLayer

- (id)init
{
    if ((self=[super init]))
    {
        // Enable the accelerometer.
        self.isAccelerometerEnabled = YES;
        
        // Get an instance of the game state singleton.
        _state = [GameState sharedInstance];
        
        // Ask director for the window size.
        CGSize windowSize = [[CCDirector sharedDirector] winSize];
        
        // Create the world.
        [self createWorld:windowSize];
        
        // Create our hero.
        [self createHero:windowSize];
        
        // Create a ball.
        [self createProjectile:ccp(0, windowSize.height)];
        
        // Create the contact listener.
        [self createContactListener];
        
        // Schedule animations.
        [self schedule:@selector(tick:)];
    }
    return self;
}

- (void) dealloc
{
    // Destroy the contact listener.
    delete _contactListener;
    _contactListener = NULL;
    
    // Destroy the world.
    delete _world;
    _world = NULL;
    
    // Nothing else to deallocate.
    [super dealloc];
}

- (void) createWorld: (CGSize)windowSize
{
    // Create our world.
    _world = new b2World(_state._gravity);
    
    // Create edges around the entire screen.
    b2BodyDef groundBodyDef;
    groundBodyDef.position.Set(0,0);
    _groundBody = _world->CreateBody(&groundBodyDef);
    b2EdgeShape groundEdge;
    b2FixtureDef boxShapeDef;
    boxShapeDef.shape = &groundEdge;
    groundEdge.Set(b2Vec2(0,0), b2Vec2(windowSize.width/PTM_RATIO, 0));
    _groundBody->CreateFixture(&boxShapeDef);
    groundEdge.Set(b2Vec2(0,0), b2Vec2(0, windowSize.height/PTM_RATIO));
    _groundBody->CreateFixture(&boxShapeDef);
    groundEdge.Set(b2Vec2(0, windowSize.height/PTM_RATIO),
                   b2Vec2(windowSize.width/PTM_RATIO, windowSize.height/PTM_RATIO));
    _groundBody->CreateFixture(&boxShapeDef);
    groundEdge.Set(b2Vec2(windowSize.width/PTM_RATIO,
                          windowSize.height/PTM_RATIO), b2Vec2(windowSize.width/PTM_RATIO, 0));
    _groundBody->CreateFixture(&boxShapeDef);
}

- (void) createHero: (CGSize)windowSize
{
    // Our hero.
    _hero = [Hero spriteWithFile:@"Hero.png"];
    
    // Add him to the layer.
    [self addChild:_hero];
    
    // Now we know the size of the sprite, work out it's position.
    CGPoint p = ccp(windowSize.width/2, _hero.contentSize.height/2);
    
    // Position him where requested.
    _hero.position = ccp(p.x, p.y);
    
    // Create the dynamic body definition.
    b2BodyDef heroBodyDef;
    heroBodyDef.type = b2_dynamicBody;
    
    // Position it where requested.
    heroBodyDef.position.Set(p.x/PTM_RATIO, p.y/PTM_RATIO);
    
    // Create the body.
    b2Body *heroBody = _world->CreateBody(&heroBodyDef);
    
    // Create the shape.
    b2PolygonShape heroShape;
    heroShape.SetAsBox(_hero.contentSize.width/PTM_RATIO/2,
                       _hero.contentSize.height/PTM_RATIO/2);
    
    // Create the definition and add to body.
    b2FixtureDef heroShapeDef;
    heroShapeDef.shape = &heroShape;
    heroShapeDef.density = 1.0f;
    heroShapeDef.friction = 0.2f;
    heroShapeDef.restitution = 0.0f;
    heroBody->CreateFixture(&heroShapeDef);
    
    // Restrict our hero to only run along the bottom.
    b2PrismaticJointDef jointDef;
    b2Vec2 axis = b2Vec2(1.0f, 0.0f);
    jointDef.collideConnected = true;
    jointDef.Initialize(heroBody, _groundBody, heroBody->GetWorldCenter(), axis);
    _world->CreateJoint(&jointDef);
    
    // Add the physics to the sprite.
	[_hero setPhysicsBody:heroBody];
}

- (void) createProjectile: (CGPoint)p
{
    CCLOG(@"Adding new projectile! %0.2f x %0.2f",p.x,p.y);
    
    _projectile = [Projectile spriteWithFile:@"Projectile.png"];
    [self addChild:_projectile];
    _projectile.position = ccp(p.x, p.y);
    
    // Create the body definition.
    b2BodyDef bd;
    bd.type = b2_dynamicBody;
    bd.position.Set(p.x/PTM_RATIO, p.y/PTM_RATIO);
    
    // Create the body
    b2Body *b = _world->CreateBody(&bd);
    
    // Create the shape and shape definition.
    b2CircleShape s;
    s.m_radius = (_projectile.contentSize.width/2)/PTM_RATIO;

    b2FixtureDef sd;
    sd.shape = &s;
    sd.density = 1.0f;
    sd.friction = 0.0f;
    sd.restitution = 1.0f;
    b->CreateFixture(&sd);
    
    // Add the physics to the sprite.
	[_projectile setPhysicsBody:b];
    
    // Zoom
    b2Vec2 force = b2Vec2(2.5f, -5.0f);
    b->ApplyLinearImpulse(force, bd.position);
}

- (void) createContactListener
{
    // Construct contact listener.
    _contactListener = new HeroContactListener();
    
    // Add it to the world.
    _world->SetContactListener(_contactListener);
}

- (void) tick: (ccTime) dt
{    
    int32 velocityIterations = 10;
    int32 positionIterations = 10;
    
    _world->Step(dt, velocityIterations, positionIterations);
    
    // For every body in the world.
    for (b2Body *b = _world->GetBodyList(); b; b=b->GetNext())
    {
        // Update our hero's position.
        if (b == _hero.getPhysicsBody)
        {
            _hero.position = ccp(b->GetPosition().x * PTM_RATIO,
                                 b->GetPosition().y * PTM_RATIO);
            _hero.rotation = -1 * CC_RADIANS_TO_DEGREES(b->GetAngle());
            
        }
        // Update the projectiles position.
        else if (b == _projectile.getPhysicsBody)
        {
            _projectile.position = ccp(b->GetPosition().x * PTM_RATIO,
                                       b->GetPosition().y * PTM_RATIO);
            _projectile.rotation = -1 * CC_RADIANS_TO_DEGREES(b->GetAngle());
        }
    }
    
    // Check for collisions.
    bool collided = false;
    b2Fixture* heroFixture = _hero.getPhysicsBody->GetFixtureList();
    b2Fixture* projectileFixture = _projectile.getPhysicsBody->GetFixtureList();
    
    std::vector<Collision>* tmp = _contactListener->GetCollisions();
    std::vector<Collision>::iterator pos;
    for(pos = tmp->begin(); pos != tmp->end(); ++pos)
    {
        Collision collision = *pos;
        
        if ((collision.fixtureA == projectileFixture && collision.fixtureB == heroFixture) ||
            (collision.fixtureA == heroFixture && collision.fixtureB == projectileFixture))
        {
            collided = true;
        }
    }
    
    // If we collided, game over!
    if ( collided )
    {
        [[CCDirector sharedDirector] replaceScene:[GameOverScene node]];
    }
}

- (void) accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration
{
    // Useful constants.
    static const float32 maxVelocity = 10.0f;
    static const int forceMagnifier = 5;
    
    if ( ABS(_hero.getPhysicsBody->GetLinearVelocity().x) <= maxVelocity )
    {
        // Setup the force x & y.
        float32 forceX = acceleration.y * forceMagnifier;
        float32 forceY = acceleration.x * forceMagnifier;

        // Alter the force based on the devices orientation.
        UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
        if ( orientation == UIInterfaceOrientationLandscapeLeft )
        {
            forceY = forceY * -1;
        }
        else if ( orientation == UIInterfaceOrientationLandscapeRight )
        {
            forceX = forceX * -1;
        }
    
        // Apply the force to our hero.
        b2Vec2 force(forceX, forceY);
        _hero.getPhysicsBody->ApplyLinearImpulse(force, _hero.getPhysicsBody->GetWorldCenter());
    }
}

@end
