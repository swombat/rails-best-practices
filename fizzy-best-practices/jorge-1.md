Youtube video: https://www.youtube.com/watch?v=QNqmAxxKzp4

Hello everyone. So last week I published this uh video talking about how we
architect Rails applications using Fizzy as an as an example and I got um several
questions about Fizzy codebase uh both before and after the video was released.
So today I would like to address some of those questions. I think some questions
uh would make for dedicated videos in the future but I selected a few that I
think I can I can go through um today and at the end of the video I've seen
that there is an area of interest which is uh the view layer in rails. So I'm going to share our philosophy and
approach um for views in our applications. So um let's go.
So uh the first question here by Matt is asking about the has one goldness um
association and and related model and um why are not using like a flag instead of
an additional record for representing that cards are uh can be uh golden why
aren't we using an an additional a boolean column I I guess so if we go to
the card model and we go to the golden concern we can find that association
which is indeed using a dedicated uh additional model which is an so there is
like another table that we are joining against uh for filtering golden cards or
for uh detecting uh whether a car is is golden or not. So um why we do this? So
there are several reasons well first of all if we used a boolean column for this it will be totally fine. This is not
like oh my god it will be terrible but I'm going to share the reasons. One thing is uh consistency.
So uh for example uh a card can be um
uh closable. So you can close a card. So for representing that a card is closable
we have this has one closure association which is using this additional closure
record. Uh in this case we went with that because when you use an additional
record uh you get like a date for free. So for representing when a card is
closed at uh which is here. So we can check what is the created at time stamp
in the record. So we get that for free. Um at some point we removed that but in
VC you could set reasons when closing cards. So you could say, "Oh, I'm closing this one as a duplicate." Uh,
and that was um stored in the in the card and we were storing that at this
model, a disclosure model. So in that regards, you could you can extend like the the quality of enclosed with
additional information. So a model or a table uh makes for a natural fit to do
that. Uh so um now with golden cards we are not
doing that. We are not quing the date. We are not quing the uh we don't have
additional information there but it's it's kind of consistent with how we are modeling data card can can be closed. So
in that regards I think it's it's it's better or slightly better for consistency. We are using the we are
doing the same for uh for example a card is postponable. So we have the not now
association um or the not now um
additional record to model that. So we keep things consistent. Another I think good reason is that is
filtering. So in fizzy you can combine filters and or you can filter cards by
multiple conditions and you can sort card cards on multiple conditions. If we
represented everything with um with columns at the card level um it will be
I mean we will have to be very mindful about um indexes like composite indexes.
So we will be need to make sure that we have the right indexes in place covering
all the columns in the right order that we can that someone can use when filtering for multiple conditions which
is kind of a a hassle uh to do. Uh this is simpler because by joining uh on
additional tables we get efficient filters just by having the right foreign
key uh indexes in place and we can combine those uh more easily right
without the the column ordering in the index being being a concern. So that's a another good reason I think.
Okay. Uh Rey is asking about uh are the rules for fixtures um when to add
fixtures or when to create objects. I would say Ry that uh the general idea we
try to follow is we try to avoid creating new records in fixtures. um
instead we try to build uh a realistic
um set of pictures and by realistic I mean it represents um data that makes
sense if you were using the application as a user. So we don't have things like
card one, card two, card three or closed card uh I don't know archived card. We
try to use names that represent um cards that a human will create. So that we
actually we the fixture system is part of our seeding system. So you can play with the
fixtures where you're using the app locally in development. So they they need to to make sense or we try them to
make sense and they should be like comprehensive enough to cover the most typical cases. So in general try having
to create records is something we try to avoid. We sometimes do for sure. Uh but
we try to avoid that as much as possible and the reason is the speed like fixtures are much uh faster than
creative creating ad hoc records because they um uh you can dump like the fixture
data set very quickly when the the test suite starts and then um you can roll
back the changes uh whenever each test runs. So that that approach is incredibly fast. Uh
uh if you created records uh when you create records at OG on every test uh
those insertions are slow are much slower than the initial dump that we do with with with fixtures. So
okay so Alex is asking about restful roots um how to design them and such. I
think this will be um this will be like the subject of a whole episode but we
are indeed um we lean towards creating restful roots like almost all the times.
Restful roots there are many benefits they play great with how HTTP work and
um a wonderful side effect or or consequence of using them is that you end up with uh small controllers that
are highly cohesive like doing one single thing. Uh and that comes by
design, right? Because you are you are um trying trying to represent like your
the resources that your application exposes exposed as um as uh nouns you
can act on using four verbs. So by by definition uh controllers remain very
small and very focused. And I think this kind of links with um what I talked in
in the last video talking about Rails architectures about how we don't use service objects we because our
controllers are already doing the same high level orchestration
uh role that service objects should should play and that they remain very
thin and very cohesive um in the way we use them. So um the question is about uh
that some models um like the comment doesn't nest inside a card but all the
comments nest inside like engagement. By the way this comment about engagement
made me realize that we are not using this engagement models or controllers anymore. That was part of uh previous
workflow we were supporting in Fizzy. So I just created a pull request to remove engagements because they were not used.
Uh but uh yeah regarding the question what this person is asking is um
um so for example if we go well this is a good example like uh for example for
postponing a card we associate this not model to them and this is in the name
space uh card not know right? If we go to the to this model uh this is nested
inside a card while other com other model like comment they are like root models right uh I don't think this is
sorry we are here I don't think this is um you know written in a stone or that
we follow very very hard rules here uh what what I think the re the the the
reasoning here is that a comment is is is kind of I I mean it depends on a card
to exist because you need a card for a comment to exist in fizzy but as an entity it um it is important enough on
its own. So for example a comment can generate events and you can get those events in the timeline and you can reach
a comment that way or um they generate activity that we send in emails. uh
comments are like they have like a substance outside of what a card is.
However, there are other models like is like engageable was back in the day but like uh uh this not now model or
goldness uh the goldness model we used to flag a card like golden like if we
removed the card prefix and name space you would say what is this goldness doing? uh is this is this something you
can attach to any model? Is this something that can that has entity outside of the card that acts act acts
as the host and the answer is no. So that's the reasoning we try to follow
but I don't know in general I think this a kind of subjective territory and maybe
different parameters have different uh views here those are my thoughts at least. Um
so Nick is asking about integrating Ruby LLM into Fizzy and yes uh so during the
development of Fizzy we explored um implementing certain AI features and we
used the Ruby LLM uh gem to do that. Uh the gem was fantastic. Uh by the way uh
it worked very very smoothly in all our explorations. Um we eventually didn't we
eventually dropped all the features we had built that were highly exploratory.
Um fizzy back in the day it had u a command bar that you could enter
commands with a certain syntax. We built that. Then we thought of introducing an
LLM powered liar on top of that so that you could use natural language to say things like close this card or assign
this card to I don't know Kevin or whatever. Uh we built we built that and
that was working pretty well. Um but uh there were it was falling short
in some other scenarios because as soon as you as soon as you have that in place um it's natural that you want to start
asking for things more uh fancier or more sophisticated uh and it wasn't covering like um it
wasn't working as well as we wanted it to work. Then um Stano explored um
another feature which was fizzy ask where um you would have like a chat with
a with a you know like if it was chaty inside fizzy where you could ask and interact with the system that way we we
used a rublm feature called tools to do that again it was working well but um it
wasn't as it wasn't working well in all the scenarios sometimes it would uh
provide like uh answers that were kind of poor or would um you wouldn't get
like the quality you would expect uh or the quality we want to set uh for our
products. So we dropped that feature too. We had su summaries we explored um
building weekly summaries of the activity that you've done. uh again it was working well in many cases in some
of the cases the summaries were a little bit meh so um we dropped that too so we
explored quite quite a few AI avenues but eventually we decided to launch
without them because we they were not good enough we learned some good lessons
and uh I know that there are like a lot of interest in in a company making AI
work uh at the level we want it to work. So, um there will be more news here in
the future, but uh that's the story of phys and AI.
Um yeah, now I have a series of questions asking about multi-tenency
uh and why did you decide not to go with SQLite? So actually Fizzy while we were
using it internally uh it was running on SQLite with a multi-tenency setup uh in
place. This was always like um a thing that uh we were exploring um or that was kind of
exploratory in nature. So the idea was like we're going to make multi-tenency work with SQLite. if by the end of the
project we haven't managed to to do that uh to to to make a to make it work as
well as we want to we are going to switch to to my SQL. So that was kind of the the idea here. Um
uh this was uh mostly the work of uh Kevin McConnell and and Mike Delesio. So
they I think they did a terrific work in terms of the difficulties they faced and
the sophistication of what they built. It was working well. Uh the problem was that at the end of the project where we
wanted to ship um there were some operational concerns regarding
how uh were we going to offer like the level of availability we want for our applications. Um so we run our
applications on multiple uh data centers. Uh we can uh so if one data
center fails we can fail over uh over the other data center. Um the databases
are replicated so that you can you know we can still provide the service um as
expected without interruptions or without major interruptions and and we have other a bunch of other uh efforts
in place to to ensure that we can offer you know very high availability
and um doing that with SQLite uh was presenting some operational
challenges that we were uncertain about. We didn't want to delay the launch uh
beyond uh what you know the date we had set and eventually we decide to go with
my SQL which is known territory for for the company. Um well that's that's the the story. Um
Marcel is asking about why not use a turbo frame with lazy loading as a pagination trigger since it's already
got an appearance observer. So um I mean the reason if you if you do
pagionation with turbo frames uh directly without anything else uh one problem you have is that you will have
uh turbo frames nested inside turbo frames inside turbo frames. So that's not going to to fly. Uh so we have a
system in place that involves an stimulus controller called uh pagenation
uh stimulus controller uh sorry pagination controller uh that kind of
uh take the frame that is going to trigger and you know move move it at the
top of the page so that you get like a sequence of turbo frames uh containing
the the pages and these turbo frames are they refresh with morph so that if you
pagionate for example in the in the activity timeline and then the page
refreshes because some event arrives you get like the the data smoothly updated
the pageinated data smoothly updated uh that way. Um
so that's what we are doing there for pagination. Uh by the way this as you
know F is open source so you can check all this AI stuff you can uh dive into
the pull requests uh you can check this pagionation code everything is in gith
uh basecam uh fizzy if you want to check it.
Uh finally well here I had two questions regarding the the view layer. One is
from Miguel which is asking that you include view logic and even HTML
snippets on your models. Is that the approach you usually follow? Uh it's not
like uh I think I know which parts you're referring to and I'm going to to review that next but in general that's
not what we do but I'm going to to elaborate on that uh next. And uh Jordan
was asking about the usage of template helpers. Uh why a component system is not needed. Uh
well and he's asking about delegate types and you know uh delegate types
there is something very exciting to bring light on delegate types that is in
the oven right now. So um I think you you will get some good information there
soon but I'm going to focus on the view on the view layer. Okay. So um
regarding views there've been like a I've seen some discussions recently
um talking about you know radius is missing like uh something like view
components because uh view helpers uh kind of fall short in some scenarios and
um erb templates are not enough. I'm going to share like how we do it and our philosophy and and some further thoughts
there. Okay. So, so I want to show you how we render this
view which is the activity timeline view because it's a view that is interesting.
It serves to show like different scenarios or how we deal with complexity when we are rendering views.
So if we go to um first to this day timeline scoped concern, we see that um
this is setting this this is invoking this set day timeline uh method that is uh setting this date timeline object
which is a plain Ruby object as the the main uh domain entity that the the
controller is setting so that the view can render it. So uh if I go now to the
controller, I'm going to go to the view because this view is show showing se several things. Um so show showing how
we deal with views pretty well. So first of all um we use um partials uh a lot.
So we try to divide our views into uh smaller chunks uh with proper names to
keep things organized just like you try to divide your long methods into uh
smaller methods uh the same level of abstraction to to make sense of the code or to make it easy to read. I think the
same pattern is uh totally something you can apply to to views. So we try to we
use partials to you know to extract uh and to make code
more readable. Uh we also use um helpers and view helpers in rail. So the
question is when do you use partial and a partial and when do you use a helper? So in this case for example if we go to
the uh uh sorry here if we go to the dame
timeline pagination frame tag uh this is a helper method this is rendering a
turbo frame um with some stimulus controller and some uh ID conventions
that's a very simple u that's a method that is returning a very simple HTML bit in that case uh helper works great in
other cases such as for example add card button the HTML you are rendering is
more substantial. So in general when the HTML to render is more substantial and unless there is uh a compelling reason
not to uh I lean towards using u templates sorry partials because they
are they they play better with with composing HTML than than helpers in Rails. Um, and actually I think that
Rails could do something uh better there like we could have we could have like something tighter to generate HTML in in
helpers. I'm not saying there is not margin for improvement there. But there is this discussion about uh whether we
should use uh view components or we should use uh because because partials
and helpers like kind of fell short in fall sort in some occasions.
Uh my take on this is that in general partials and helpers work great for us.
Um I think we cover probably 95% of the
needs we have in our applications in the way we work. Um whenever people talk
about uh replacing this with something else, I think that what we would have to
see is something that is so much better is like night and day night and day
better than what we have now in order to to embrace it. Uh I think at least that that will be my my view. uh think that
you know in 377 signals in the way we work um designers designers of 37
signals they have a lot of agency and autonomy to to make progress. I uh you
can go to to the fishy repo at fizzy at bascanfishy and just try to s uh search
uh close. I actually can do that. Uh if if I go here and I search uh closed pull
request where the author the author is uh Jason Cinders which is one of the
designers the the other one is 222 pull requests. Uh if we go to and Smith which
is the other designer 2072 pull request. So designers like they get a lot of
things done uh because they um work autonomously
and um they are of course they are not normal designers they are incredibly talented um they are experts in HTML
they are expert in CSS they can do Ruby they can do Rails they can do JavaScript. So they are uh they are
folks with skills let's say but uh I think it's very important like this uh
to us the view layer this HTML templates are like the common ground where
designers can iterate over and we programmers step in and try to help to
organize things or to tidy up things but in general the common ground is this is
h this HTML erb templates. So um if we
embraced like a more programmatic view to build these rails uh sorry these
views uh I think that common ground will suffer. Okay, because it will be a more
familiar way of building uh UI UI bits maybe for a programmer or it could make
for cool things at the programming side but at the expense of losing you know the familiarity and uh the powerful
declarative nature of HTML that we all are familiar with. So uh well I agree
that probably there is things we could do on you know to make helpers more uh
view helpers or something that helps you generate HTML programmatically
you know more easily. I I don't discuss that that would be a benefit uh or that there there is some potential there for
for making things better. Uh I'm skeptical that
you know replacing this like this uh index car add card button with a view component that does this with a class in
the middle. I'm skeptical that that's that's a life-changing approach to build user interfaces and because it's not
like you know uh significantly better.
I don't find it like a very I don't find a very appealing case to embrace view
components or you know other uh systems of components for views in Rails to
embrace that as a general way of building views. To me that's not an appealing path uh with the current state
of of things. Um they normally say that um a benefit of view components is that
you can test them. We the thing is that we rarely test our views like we um we
test our views through integration tests uh in the so test testing rails controllers essentially but we rarely we
we focus on the expected uh outcome in terms of database modifications uh kind
of HTTP response very rarely we check like the views uh the content of the
views to make sure uh we are generating the the views we want to generate
Um the reason again is that building um
uh building the reason is that um
views are like uh we keep iterating on views. Designers keep iterating on views even after thing something is shipped
they keep coming back and changing things. Uh we don't want to put uh to
write tests that get in the middle of that. Okay. So and also another reason is that this is not like uh lacking that
level of testing is not a source of a recurring source of bugs for us. So in
our experience this works pretty well in the way we work uh you know with our approach. We are not missing view tests
or tests for view specific things uh isolated from controllers so that you
can build a comprehensive suite of tests for your views. That's not uh a need. we
have so kind of um that kind of uh uh
goes in the line of we are not missing uh view components or or similar technologies.
Um something I wanted to show you is that we do sometimes this is rare but we
sometimes find that helpers fell short for organizing like uh complex view
needs and this is actually this view is actually uh an example here. So uh let
me show you how we render a day. Uh if we go to events day to the events day
template um we go to this event day timeline columns you can see how what I
was referring about the compos method philosophy here. This is doing two things. We have two partials uh at the
same level of abstraction. This is easy to understand. It keeps things organized and it works very well for for us. So if
I go to the columns um template here, we can see how this is saying render this
column um partial and I'm passing this uh column day timeline added column day
timeline added column day timeline closed column. Okay, so here we can see how the the view is is asking the domain
entity for this column object that it can render. Okay, if we go to those
methods and we go to see how those methods are created. Uh we can see how
uh this is returning a column again a plain Ruby object that you can ask for things like give me
your title or give me give me um group the events by hour so that I can render
them. So if I go to the view we will see how these templates are interacting with
those column objects. So uh you can totally make the case that those column
object this this column object here this is acting like a presenter object right.
This is wrapping like a this is offering to the views um this is offering to the
view layer an API that is built to satisfy the view layer needs. So this is
like a kind of a presenter object like in the like with the service object case
that I talked about the other day. uh we don't use the presenter bit in the
name. So we don't call this a column presenter just like we don't use sign up service for for the signup thing. We
just these are just plain objects uh that we are using to make rendering our
views uh you know nicer and to to keep the code more maintainable.
Um if we go to again if we go to the to the
view you can we can see how this is kind of more or less easy to
follow and easy to understand which is the the whole goal and so it means it's it's easy to to maintain um with this
approach now I want to point out that doing this is rare like it's rare that we resort to
that we normally do this when we are using helpers uh we using helper helper
objects normally you start to find that you need to create helpers that invoke
other helpers and they are always passing the same data through. So sometimes that's a good signal that you
need that some missing abstraction is is is there right like you're missing some
abstraction there. So in this case actually if you go to the pull requests or to the commits to these views you
will find that was actually the case. We had a system of helper objects. It was kind of messy. At some point we said
this is super messy. We are going to extract these things or these additional abstractions. Um
um okay. So that's one example. Uh another example of this let me let me go
to this view when we are rendering. No it's not here. Um
this is this is the rendering the column. Um I want to show you when we
are render Oh yeah here here we are rendering the events specifically. Okay. So um
when we render for example an an event specifically I'm trying to
locate the code which is here. Okay. Um
yeah here here's the line. Okay so when when we are rendering an event here the
event the body of the event like you will handle this or you assigned Kevin
that that piece of text is rendered here. Okay. So here this is another
example where we can ask the event model description for this user because the
description you see changes depending on who you are and we are rendering and to
HTML view of that description. If we go here, we're going to find again that
this description for method which is at the event model is returning this description object and this description
object has two methods. One to render as HTML and another one to render as plain
text. Uh this is because for rendering web hooks we use this version and for
rendering the views we use this one. So again this is another case where we had
like a salad of helper methods. It was quite messy. At some point we said okay we are going to refactor this. We are
going to stack this description entity and these are presentation concerns and
this is served from a model. This is rare we it's not that we are always
doing this but in this case it plays I think it's it's a good design. is a great design because we say oh event
give me your description for this user and we render this as HTML just like you
can uh render the HTML or the plain version of an action text attribute
right this is kind of similar to that so um I think this for the rare I think
these two scenarios are the only two scenarios where we are doing this creating this sort of presenter object
um I think that Uh, in general templates
and helpers work great 90% of the of the times and you can always create and we
certainly do create these additional uh kind of helper objects or presenter objects or however you want to call them
these additional objects that you know perform a proper implementation of more
complex behaviors. Okay, so that's this is something we do but again if you check our views this is rare. Okay. Uh
we we are templates and and view helpers uh all the time. We use that all the
time. All right. Um so I think we are
going to Oh yeah. Uh there was a last question here which is uh testing. How
much is enough and of what kind? I think this is a great question by um Miguel.
Um I think there is a great quote by Kent Beck talking about tests um like
the gold of tests is uh giving you confidence about uh your system. So this
is important to to have in mind because sometimes uh you know additional traits
like uh the speed of the test suite or the the coverage or um other aspects uh
become like a goal themselves. a goal by by themselves and
you need to keep in mind that tests the tests are they are not free like they they take time to write and they take
time to maintain which is very very important. So uh I used to have a more naive and purist approach towards
testing when I uh started many years ago or when I started with with automatic
testing at least. These days I really value uh tests that test the real thing.
uh integrated tests that kind of um exercise like the full stack and that
you can execute uh as if you were observing the system as a black box that
you interact with and where you observe the outcomes. Okay. So, uh I don't love
uh tests that are based on stabbing the internals of the class the classes
unless that's necessary of course or because you you need to mock out to mock out some dependency or something like
that then it's justified but in general I like the I don't know model tests that
are testing uh you know that the the database is
get the data uh you expect if you have a system of objects I like testing the the
the entity that is orchestrating the system of objects to try to see if the outcome is is what I want to see. Um so
in general I don't think it's a good smell that if you have a that if when you are going to change the internals of
an object uh tests broke. Okay, that's kind of an smell that you're not doing things right. So tests that uh test the
real thing being mindful about uh what to test and what not to test because because tests aren't free and uh I think
it's hard to give very strict deadlines but if you check uh our test suite in in
FY um what you will find is is uh
controller tests which are integration tests exercising our endpoints and uh
trying to see if the outcomes is what we expect. Um
uh you're going to find like unit tests for for models that again trying to
follow this philosophy and that's pretty much what what uh we
are doing. We are we have like some smoke tests um very high level. We have
experimented with system tests quite a bit. uh eventually we don't think like the tradeoffs are worth it. I they bring
value. They they are valuable but they are also slow. They can be brittle. They are slow to write and to maintain and to
run. And eventually we said like we decided that they were not uh worth it.
Um a final note I wanted to um comment is that uh none of this I think nothing
in software is like hardcore rules you must follow all the time. Okay. I'm uh
sometimes with with general advice you sometime take the advice too far. I want to show you a very recent test of
something we uh of a pull request I actually merged today uh which is related to enforcing storage limits in
Fizzy for the Fizzy uh sorry for the SAS side of the equation for the SAS service
that we run on on Fizzy. The pull request is in GitHub and you can check it. Uh the thing is that when you are
going to create a card uh depending on of the storage you are using uh we want
to show a certain notice and depending on the card count uh you're on your card
count we want to show certain messages for example inviting you to upgrade if you are close to reach one of those
limits or directly preventing you from creating cards if you are out of limits
and the bureau was kind of involved in that regard and to gain confidence over
the system, I decided to write a test uh which is uh I think it's card creation
test. Yeah, here it is. So, uh this is a test that is doing two things I said I
don't like to do. One is using uh an stabbing certain certain internal not
not not internal but stubbing certain method uh that I could this is not a
column I could write uh easily. So I decided to go with a staff to simulate different storage uh situations because
with the system we use to track storage we are not storing that at the account level. There is a more involved uh
system under the hood and uh I decided to go with that uh to to simulate
different uh storage situations uh because it was the easier option at
hand. Uh another thing is that here in this view I'm indeed and this is the main the main purpose of the of these
tests I'm checking that the output in the I'm see I'm checking that I'm seeing
like the right message I expect to see in the output which is something we we rarely do but in this case that was what
I wanted because I wasn't I wasn't certain about like uh is this robust enough so it's an example of a test
where I'm doing two things that I I have pointed out that we rarely do so you
know there is no rules that you say that you need to fulfill all the time uh or
you know never do that never do this people tend to be very categoric and in
software I don't think that plays very very well um okay uh this is all again
uh the video took longer than I expected I hope you find it useful um I wish you all merry Christmas and thank you for
your time take