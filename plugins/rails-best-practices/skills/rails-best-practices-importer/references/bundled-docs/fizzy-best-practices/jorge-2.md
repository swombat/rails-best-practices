Youtube video: https://www.youtube.com/watch?v=dvPXFnX60cg

Hi, this is Horge from 37 signals. So today I'm going to talk about uh how we
architect our rails applications. So last week was a special week because we
launched Fizzy. Fizzy is um our take on a campan tool. Um we launched it uh last
week. The reception has been phenomenal and uh something that made the launch
very special is that for the first time we released the source of the service uh
uh as an open source project. You can check in GitHub at basec camp uh fishy.
So you can um clone the project, you can check all the history of comets, pull
requests, everything is there. So I'm going to talk about some topics
I've written about. If you go to uh dev37s signals.com you will find our dev
blog and there you can find the code I like series which is a series of uh
articles I wrote about all these topics. Uh the central one is vanilla ra is plenty and there are other articles like
touching or expanding on on different uh aspects of of the whole idea. When we
talk about banilla rails, we actually refer to two things. One thing is our preference for um our preference for uh
not using uh third-party dependencies and going with rails defaults. So for
example, we go with rails uh um view helpers and templates instead of view
components or we prefer minest to ourspec. Uh that's one side of the
equation. The other side of the equation is that we uh architecturally speaking,
we don't add uh new artifacts to what Rails and Ruby already provide when uh
architecting our applications. Okay. So, I'm going to focus on this uh latter
side of the binar rails equation. And uh well since Fizzy is open source
like it's a great opportunity to discuss these topics uh you know looking at
actual code and actual interactions and seeing how the application works. So I'm going to show like different um
different parts of the applications of the application to make different points. Uh so I'm going to start with
the first one and for the first one uh let me open the inspector tools. Uh I'm
going to show you how to drag. I'm going to drag a column from uh this is running
locally in my box. This is the uh cloned project from GitHub. I'm going to drag
uh a card from one column to the uh maybe column. Okay. And I want to
show you what happens. Okay. So this is uh sending like a post request to this
endpoint that I'm going to open. So this is like uh dropping the card number
seven at the string column. That's what the resource is representing.
If we go to the code base, I'm going to open that controller. Oh, sorry. It's
not here. It's here. Streams controller. Um
inside drops. Okay. So I wanted to open that this file. Okay. So,
so from an architectural point of view, and by the way, this is uh something this is an approach I've learned at 37
signals. Okay. So, this is the credit should go to David and and other amazing
parameters in the company such as Jeffrey Hardy. I'm just trying to articulate what I understand the 37
signals approaches. And the 37 signals approach is not that u radical or
revolutionary. See the 37 signals approach is about
placing the domain model at the center. Okay. So the domain model of your
application is the central part of your application and this is the core idea in
domain driving design. the movement and uh the paradigm that was popularized in
the early 2000s uh in in the book um domain driving design by Eric Evans. I
know that book had a tremendous influence on David back in the day because it's it's a book he often
recommends and that's what the book recommends like make the domain model
the central part of your application meaning that you should put you know
most of your effort on making that your code evoke uh the problem you are trying
to solve right so in this case this is a campan tool so we try that our domain
model uh reflect like the behaviors and the nouns we are using when we are
discussing the product. Um
so if you make the domain model the central part of your application
a key question is how do you connect the external world with your domain model?
So um that's what in a rails application um that's what you
that's a question that you can answer uh at different parts of the application the most typical part are rails
controllers right in a rails application rails controllers are what connect like web requests with your application so if
you check our rails controllers you will normally see like very thin controllers
exercising directly our domain model invoking some business logic that you
need to invoke to satisfy the needs for the request. So in this case for example
in this case we are dropping a card in a column. So you will find this is the
business logic we are exercising. We are saying card send back this card. I'm I'm
we are sending the message send back to triage to discard. Okay. So that's what
you will find in most of our controllers. Well, another typical scenario is more
simpler scenarios like for example if we go to the comment controller. Um
so when you for example when you create a comment in a card or when you update a comment in a card um you will find like
this is like pretty vanilla uh scaffolding rails code. We are just
updating or creating the record directly with totally does the job when the
interaction is as simple as that. So if you want to store some data in the database, some record in the database,
totally fine to use active record to just do that. But it's quite often the
case that we need to do something more complex. So in that case, we want to to see that domain logic encapsulated in
the domain model and we exercise it directly from the race controllers. And
this is uh the subject uh of in my opinion a controversy that is not really
justified which is like the the whole debate about service objects. Okay,
application service objects and uh I think the the I think it shouldn't be as
controversial because essentially I mean if you go to DDD and if you use
application level service objects properly so the idea of a service objects is that you build this
application layer that connects this the external world with your application okay so uh that's exactly the role that
rails controllers fulfill right but domain driving design was written before
even rails existed. So its proposal was to use service objects and service
objects uh in theory or in the original proposal of DDD should do exactly what
we are doing here. They should orchestrate how you invoke how you orchestrate um domain entities to
satisfies your business logic needs um at a high level or also they should
contain like infrastructure um code such as for example persistence in the case
you are separating the persistence concerns from your domain model. So applica the application layer is in
charge of dealing with that persistence. So let's write this in code for a second
because I want to make a point that I think is important. So imagine that instead of sending the message send back
to triage, we were using a service object here. So I could say something
like I don't know cart send back to triage. Okay, something like this. I'm
creating a new service object send back to triage and I'm invoking it on the card. Uh
I'm going to create the service object. This is helping me a bit. Uh I don't
want this. Imagine that I create a constructor for that. And that now I'm going to write
the call method. Okay. See like uh the LLM is completing that uh and kind of
enforcing the point I want to make. If we were using a service object in the
way DDD proposes you should use a service object, it will be like this. So
we would have replaced the single line for a service object that invokes that
single line because service objects are not meant to implement your business
logic. Service service service objects are meant to orchestrate the entities in
their domain model that implement your business logic which is completely different. Okay. So you want your rails
controller to remain thing and you want your service objects if you are using
them to remain thing. Okay. uh that's why I don't really understand the controversy or I don't really understand
how would you how you would justify the service objects are such a life-changing idea right because they are fulfilling
the same role that race controllers are already fulfilling which is
orchestrating at a very high level what the service world what the domain your domain objects do. Uh now if you were
not using active record and you were using an alternative approach to active record where persistence is completely
separated from um your your business uh sorry your domain model then yeah here
you maybe you would have a card repository or data data access object when you say
okay save me the card and maybe the the framework you're using is tracking the changes in memory. or whatever and you
will persist them like that. That's a whole different discussion that I might I might touch on other video. We use
active record. We don't need that. uh in our case with this approach if we if
you're using Rails controller like this service object in most cases are uh
boilerplate code because you are just wrapping one line of code or two lines
of code or three lines of code with a whole class to achieve not much benefit
but if that's your thing I respect it uh please use them we don't we don't
because we actually we care about boiler plate. We we care about reducing solutions to its essence. And I think
this is like a worse design uh and worse overall quality. But it's not such a big
deal. Okay. What's the big deal with service objects? The big deal with service objects is when you propose to
use service objects to contain your domain logic. Okay. So if we went uh
here to uh the move back to triage method
um this is not finding it. One second.
It's no sorry it's it's in um
triageable concern. It's here. Okay. Send back to triage method is here. I don't know why Ruby mind wasn't
navigating to it. So so yes. So if you take this uh code and
you say okay the service object is going to implement that code right. So uh we
are going to do this in the service object and of course because we are using service objects instead of sending
the message resume to the cart to make sure it's not postponed uh we are going
to say cart uh I don't know resume
uh okay I'm going to invoke that service object too so suddenly so if you do that
with which surprisingly is the is the advice I the uh service objects
defenders advocate for over and over which is implement your domain logic um
your business logic sorry in the application layer of your application
then you are making your uh domain
models your domain entities you are um making them empty regarding behavior and
you are making them data holders which is a problem which should not be I mean
this should not be controversial because this is a problem that has been known for years is is a problem that was
highlighted by Eric Evans in the original DDD book I've seen this problem discussed in every DD book I've read uh
Martin Fer wrote a very famous seinal article called anomic domain models in
2003 I believe uh before rails was even published and and they talk about this
problem because many folks end up doing this, doing this. And if you do this,
you suddenly are opening a, you know, a full can of worms uh in terms of um
design problems because this is a poor design. Instead of having a proper domain model, what you now have is a
very flat long list of small operations where you either don't reuse code or you
create a lot of coupling within between service objects to satisfy your domain
needs. It's going to be very very messy. So uh
yes at least if you I think it's important that at least if you want to use service objects at least you should
have in mind what's the idea with service objects and the idea is not implementing your business logic you
should it should be orchestrating like one two uh domain entities three domain
entities to to per to to perform some um operation now in our case as I said we
don't to do this we just uh uh do things we just interact with the domain model
from the controller. in this case is one line which is the most common case along
with uh what I show you in the comments controller case like interacting with the records directly in some of the
cases like for example when you uh in the B controller I was looking today
sorry not here BS controller here uh um
I was looking today for examples of controllers like doing more than one line of code on the domain model. This
is one of them. So when you update a bolt in in fizzy uh you update the bolt
params and then you uh invoke this revise method on the uh accesses
association to grant and revoke permissions for the list of users you submit with the with the form. In this
case, it's a controller. It's two lines of code. Uh the important thing to me is that it's exercising domain logic about
how to review permissions at the domain level. Now if you want to do this here
for us is totally fine. If you want to extract a service object a service
object with these two lines of code that's still fine. If you want to create a form object to do this that's fine
too. But please um don't advocate for implementing the
domain logic in service objects. That's a that's a I think something especially
the folks that don't have much experience and then following the advice of service objects are your the solution
to all your problems. They are not they actually if you don't know how to use them you I think you are going to end in a in a worse place that that the place
you started at. Um so in our case controllers exercise the
domain models directly. Um sometimes for I was going to say just another example
which is a sessions controller. Um in this case uh so there is a path here
where we are creating a new signup uh in the system and to do that we are
invoking this signup operation sorry this signup object where we invoke this
create identity uh to create an identity in the system so that you can that's
actually like creating the user in the system. So this is not I mean this is
not an active record object at all like we use a lot of plain Ruby objects. So
we don't discriminate within between active record objects or regular plain
Ruby objects. But in this case the point I want to make is that sign up is not I
mean it's not a domain entity. It's not identified is it's more like an operation
um a domain operation that we want to satisfy that we can't satisfy sending a message to an entity. In that case, it's
totally fine to create a this will be like a domain service in DDD, but it's
totally fine to get those objects in place. We try to we don't use the the
term service. We don't call them signup service and we don't have methods like call. We prefer to use more semantic
terms like signup dot create identity. That looks sounds better for us. But
other than that, yeah, we we are using services. I mean, if we have to represent a domain operation that
doesn't fit in an entity, we create a object for that. And you know, that's kind of a service if you want. Uh but
what you get are controllers with little um little code
orchestration or orchestrating uh domain level behavior at a very high level.
That's our that's our uh what we try to do and the most typical case you will
find in our in our controllers is this. Okay. So um now
if you if you go with this approach, one problem uh some people complain about
and rightfully is that hey but if we place a lot of behavior in our models,
there are certain models that are going to be so big so doing so many things
that are going to violate the single responsibility principle in so many ways that this is going to be a maintenance
hell. Okay. And in that regards we I can share some techniques we use.
So um the first technique I want to talk about are concerns. Okay. So concerns if we go
to this send back to triage uh model we can see that that's uh that's in a uh in
a card triageible concern which is in the card folder in the mo in the models
folder. So if we open the card model uh you will find the triable concern there
right um the triable concern there. So what we are doing
so we use concerns in two ways. Okay. um in in in our codebase. One way is uh
like this case we are showing here we use concerns um to compose
um to compose traits traits or roles
um in certain domain models to organize those the behavior corresponding those
traits or roles. uh to organize th those behaviors in cohesive units okay that
are contained that are contained that slice of business logic for that uh
domain entity. So that's that's one way in which we use roles. So for example
here in a card we can find that a card is postponable. So if you if you go to
that concern you will find well in this case scopes and an association and certain methods that are related to
postponing or resuming cards. If you go to the triangible concern we were at
those are well the same association scopes methods that are related to uh
the this slice of functionality. And the first thing you get by doing this, I
mean there is an obvious advantage which is that you can organize large API
surfaces uh in smallers in smaller units of units of code that they are easy to
maintain and reason about. So for example, if uh I can go to the
triageable test where I have the tests organized for this trait of cards of
being triageable, that's a an advantage. uh on a higher level a big advantage is
that you get this high level module um cohesion um in your code. So um by doing
this I can go to this triable concern and I get things that belong together
together in the same file. So for example, I can get the triage scope that
is saying, oh, this is query the cards that are active that have a column and
then I have this query method triage that is checking the same thing. So if I
went to change this condition, I want to change this condition. So it's very very
handy that they are together, right? It makes sense for me as a human who is trying to alter the system or trying to
understand the system. that's cohesiveness of the kind you want to see in your your codebase. So um that's an
advantage. Another advantage is that they are very lightweight. It's a matter of uh um you don't need to create new
hierarchies of of objects or new instances. You can you don't need to define this role object that wraps the
original object to decorate it. This is lighter than that. uh if I go to the
card uh object I have like this triageable concern which is a single
file and it's injecting this behavior relating to bin triage things are organized it's easy to understand it's
cohesive uh we use them a lot so that's one day we sorry one way we use concerns
uh another way we use uh but by by the way this is not to mean that we organize
all the behavior in all the classes with concerns so that you can place behavior
in the in the main class right uh we so in this case in the case of card card is
like bold those are those these are central entities in our domain model so
they have a lot of behavior and um they have a lot of concerns in other cases
you won't find this I I don't know uh well user user is another kind of
central part um or or central entity. Um if I go to let me check another for
example identity identity is only mixing two concerns. It's totally fine to have
like a main uh a main body of methods in
in domain models by by default and using concerns for kind of um secondary traits
or relevant traits but that are not related to are not that much related to
the core of what the entity model is trying to to do. But in the case of
central uh entities, you will find a lot of concerns because uh they are very very handy
you know when you have a lot of methods to try to keep those organized. Okay.
But so this is a case of using uh one one way we use concerns. Another way of
using concerns is the original mixing u notion in Ruby which is a way of sharing
code among classes. So that's we use consens in that way too. So if we went
to the streams controllers that we were originally at the controller layer uh we
have this cardcoped concerned that we are using uh at many
places as you can see we are using card scope uh this card scope in many controllers and this is essentially
injecting this before action to set the board so that sorry to set the board and to set the card so that you can use the
card directly by just including including the concern. That's one way of using them. We also do this at the model
level, but not um I mean this is um we don't do this as much at the model level, but we definitely do.
So um uh for example, I'm going to show you something here. If um if I grab a
card and I say uh hey Jason
and I send a message for JSON. Oh the problem is that let me clear this
notifications because the notification was already there. So uh JSON hey there.
So yeah you can see how this was uh this showed up here. Right. So why that
happened? uh what why this h how this happened right um if I go so that's
that's submitting the comment we have a system in place that is extracting the mention and creating the mention model
this mention model includes this notifiable concern which is the second
uh code reuse scenario I was talking about if we check the not notifiable concern it's in the concerns folder and
uh we can find that uh events and also
um mentions are mentions and mentions are and events are two notifiable
objects. Okay. Now, sometimes when folks talk about concerns, they kind of oppose
concerns to to other techniques as if they were opposing um alternatives like
should you use concerns or should you use object composition? Should you use
concerns or should you use I don't know service objects. The thing is that
concerns um are a fantastic way of organizing like
large API surfaces in a way in a cohesive way. But concerns play very
well with object uh orientation techniques. Um so for example the fact
that you use concerns uh is not an an an obstacle to
building um systems of objects for example that you can compose to satisfy
one of those highle methods that you are exposing through your domain entities. So you can combine you can totally
combine object-oriented programming object composition with concerns and actually that's what we do. Um I'm going
to explain this with u with with a couple of examples uh that are also tied
to to to using callbacks in this case coincidentally. So we can talk about callbacks too. So uh this notifiable um
concern that we were using to reuse code is inserting this after create comet uh
notify recipients later um callback. So this is invoking this method and this
method is invoking this job. Uh if we go to the job we can find um again this is
like a controller to us. This is exercising the domain model from the boundaries of the system in this case to
execute some domain model logic as synchronously but it's the same we want
to see like a thin job just invoking some domain entity code. That's what we that what you would
normally find in our jobs. So it's kind of the same. We are exercising the domain model from the boundaries of the
system. Same if we were in the in a race console, same if we were in a script. That's what we want to see. So we are
getting a notify of object and we are sending the notify recipients message. Now if we go here you can see how the
point I want to make is that here we don't have like I don't know um 20
private methods or you know a lot of lines of code invoking this notification
system instead of that this concern is passing that message of notifying
recipient is delegating the work to a notifier entity a notifier object object
that is going to take care of that. And if we go to that for message in notifier, this is a class method that
depending on the of the source of the notification is creating um a specific
notifier object because we um for example, if we go to the mentions
notifier, it's a notifier. So it inherits from notifier but is overriding
the the recipients method. meth and the recipient's method is taken a template method. Okay, template method that the
parent notifier class defines and sorry expects when it's notifying folks it's
expecting this recipients method to exist and that recipient's logic changes
depending on the kind of source you have for the notification. Uh so we model
that system like that. So you have like you have like a system of four objects,
a design design pattern which is the template method. You have a hierarchy of objects and everything is hidden behind
this highle interface that we are uh organizing with a concern. So both legs
are important. Okay, concerns for organizing the code and proper object
orientation. I mean not proper I mean object-oriented techniques for and
patterns for trying to get the code organized, understandable, maintainable.
Um all right. So, uh another example I can
show is um I wanted to say to to share a
similar well a different but kind of similar example which is the stallable
concern. So in fizzy a card can be stalled and for a cart to be stalled it
means that we have detected an activity spike at some point and then the card
went cold. Okay, nobody commented nobody there was no activity. So we consider that that card was was installed and we
like to I mean we show a bubble in the card indicating that okay that's part of our uh part of our features and of our
domain logic and how do we implement that so uh in the stallable concern we
are using a callback again and when a card gets updated we detect activity
spikes later. So we detect these activity spikes and we record an activity spike when it happens. Okay.
And depending of when the activity spike happened, we show that that bubble. Uh
that's the how the system works. So I what I wanted to show is that well this is invoking a job. Same case this job is
invoking this passing this message detect activity spikes to the to the
card. And here again we are using object composition. we are uh delegating the
work itself to its own specialized class which is this activity spike detector
and if we went there we will find the logic. So we will say oh is an activity
spike happens when the card is entropic and uh multiple people commented or the
card was just assigned or was just reopened. We used to have like a more
involved logic here but we simplified it at some point. Doesn't matter. The case
is that the point I want to make is that using concerns
uh is not that does not mean that concerns are the silver ballad that are going to solve
all your modeling needs. You really need to use like additional systems of
objects to keep your code maintainable in in most you know applications because
certainly you don't want to see concerns like with thousands of lines of code and
having chunks of methods implementing different slices of functionality.
That's not the idea. Okay. idea is organizing large API uh surfaces
into cohesive modules and those modules serve as the entry to either very simple
logic or systems of objects that are fulfilling the task. Okay, that's uh I
think the whole idea behind of uh I mean that's the problem with the problem with
this is that it's hard to offer resides about how to proceed because we are balancing a lot of things where we are
designing software designing software is very hard but I think that's a good general idea okay I can share
um all right and in both cases I touch on callbacks callbacks are um one of
those rails techniques that are uh again controversial um because it's true that uh with
callbacks you can create problems in your codebase callbacks introduce indirection so you don't you don't want
to orchestrate like complex flows with callbacks those are uh I mean there is
certainly a way where you can shoot yourself in the foot by uh using
callbacks if you use them to orchestrate a lot of things and you can find yourself in um you know complex
debugging sessions trying to understand you know what's going on. So that's
definitely a problem but the conclusion there is not never use callax is that
the conclusion is use callbacks when they are the best tool for the job and in this case you think about it like
forget about rails forget about I don't know forget about the specifics of the technology is if as a human you're
saying you're trying to say oh I want to detect an activity spike whenever the
card changes or oh I want to notify folks whenever a notification uh um
sorry whenever um a notifiable object uh changes and it's subject to have generated some notification
then callback is a perfect fit I mean it's it makes sense to use a human to say oh yes whenever this model changes I
want to inject this logic so if I introduce some new way of commenting on
a card um the activity detection system is going to keep working. So that's a
good design, right? So callbacks are are fantastic when they are the right tool and I definitely encourage you to to
consider them and and have them in your in your toolbox.
Uh actually like for example I was thinking right now that in if we go to the triageable concern uh in this case
so when you send this is the original I mean the first example I shared when you send a card back to triage we are
tracking the event this is explicit code so in this case we are tracking the event with an explicit invocation we are
not using callbacks. So callbacks the fact that we have callbacks available does not mean that we use
callbacks all the time. Okay, we are mindful about when to use callbacks. But when they are the right tool, they are
an amazing uh an amazing tool to to have and to and to leverage. So um I
definitely encourage you to to use them. Okay. So, um
I think there are um I had a bunch of questions in the I I asked in in in
Twitter in next if if some people had questions that I want to touch on and
and I think I'm going to record a video for uh for answering those another video, a different video. Uh because
this one is taking already quite a bit of time. So, uh I'm going to to to stop
here. Um um I hope you like the video and I hope you find it useful. Uh thank
you so much for your time. See you.

