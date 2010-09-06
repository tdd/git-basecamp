Git-Basecamp
============

Git-Basecamp is a script trying to help you streamline your time-logging to Basecamp.

The idea
--------

Say you have a project in Basecamp, you enabled time-tracking and are trying to enforce it for all developers on your project, just so you get a better idea what time goes where, if only for anlysis purposes.  The problem is, most people hate to type things twice, and developers who already try and Do The Right Thing™ by using descriptive commit messages don't want to have to switch to yet another tool every time they commit stuff (which, if they're using Git properly, should be pretty often). So let's spare them!

Workflow
--------

1. You commit stuff locally using good ol' `git commit`.  Your message ends with a specially-formatted tag intended for this script.
2. Your commit message, minus the special tag and with the commit’s abbreviated SHA appended, gets logged to Basecamp, using either a work duration you specified, or deducing it from the time of your previous commit.

That's it!

Sounds good? Read on…

Setup
-----

To run this script, you only need the following:

* Ruby
* API access enabled to your Basecamp account
* Your Basecamp URL and personal API token, plus the project ID for each project you're logging time to

### Ruby

So you need Ruby installed and available.  I went to great pains not to require anything more than that: no Rubygems, much less nice stuff like ActiveResource.  You also need to run on a Unix-like system and to have your `git` binary in your default execution path.

If you're on a Linux, UNIX or OS X box, you most likely have a recent-enough version of Ruby installed already.  Just check by typing the following in a command line:

{{{
$ ruby -v
ruby 1.8.7 (2009-06-12 patchlevel 174) [universal-darwin10.0]
}}}

Any Ruby from 1.8.6 on is fine.  If you don't have it installed (what kind of system is that?!), [head over here](http://www.ruby-lang.org/en/downloads/) and install it; it's pretty fast and painless.

### "Installing" the post-commit hook script

Then go ahead and grab the script (the `git_basecamp_time_logger.rb` file at the root of this project) and put it anywhere you want (e.g. in your home directory, if that's specific enough for you).

Now, on whatever repository you want this hook to work, you need it invoked from the repo’s _post-commit hook_.

If you already have such a hook in place, add an invocation to the script from your hook’s current code.  If your hook is in Ruby already, you'll need to explicitly load my script, then execute `GitBasecampTimeLogger.run`.  If it's in shell scripting, you’ll need to run it through the Ruby interpreter, something like `ruby ~/git_basecamp_time_logger.rb`.  For other languages, I'll leave it to you.

If you don't have a post-commit hook yet, you could just make a symbolic link!  Say you're in your repository's root directory and you put the script in your home folder, that'd go like this:

	$ ln -sf ~/git_basecamp_time_logger.rb ./.git/hooks/post-commit

### Configuring your Basecamp access

You need a minimum configuration for this to work. The script needs to know:

* Generally (global Git configuration), what you Basecamp URL and API token are;
* Specifically (local Git configuration, per-repo), what Basecamp project you’re working on.

By default, Basecamp accounts do not enable API access.  Get your Basecamp account’s owner to check the _Account_ tab from the Dashboard; around the bottom of the page there should be a _Basecamp API_ section to make sure API access is enabled.  Then to get your own Basecamp API token, simply go to your _My Info_ tab, and you should see a section at the bottom saying _Authentication tokens_, with a link you can click to display your tokens.  You want the first one, the one for the Basecamp API.

To setup your global Git configuration for Basecamp access, you'd go like this (replace as appropriate):

	$ git config --global --add basecamp.endpoint  https://your.basecamp.url
	$ git config --global --add basecamp.api-token yourlengthyhexadecimalapitokenhere

Technically, the script also needs your "person ID" to log time, but because your API token is personal, it will ask Basecamp for it the first time, then cache it in your global Git configuration.  (Unless you explictly forbid it to, but why would you?)

Then once per project where you set up the post-commit hook call to your script, define which Basecamp project you're logging to.  This means getting your project ID, which is fairly straightforward: when you're browsing it, your URL’s path should start with `/projects/xxxxxx/`.  This _xxxxxx_ is your project ID.  So set it up locally:

	$ git config --add basecamp.project-id xxxxxx

OK, you're ready to roll!

Your first time-tracked commit
------------------------------

Anytime you commit with a message that ends with `[BC]`, the script will try to log your dev time to Basecamp.  The shortest form of the tag is, indeed, `[BC]`.  When you just put that in, the script will attempt to compute your dev time from the time elapsed since your previous commit.  If there is no such commit, it will explicitly fail to log.  Your time will be assigned globally to the project, without any particular task (unless you have special configuration in place, we'll see about that later).

Here's a demo session:

	$ git commit -m "Made the animation smoother on iOS [BC]"
	Logging 0:45h of work…
	Time logged!
	[master 4f17db2] Made the animation smoother on iOS [BC]
	 1 files changed, 1 insertions(+), 0 deletions(-)

Notice the two first lines.  If you're in a TTY (an interactive terminal, basically), "Time logged!" will even appear in green, to stress something successfully happened right there.

Tweaking time
-------------

There are essentialy two situations when you don't want to let the script compute work duration entirely on its own:

* This is your first commit, hence it _can't_ compute it.
* Your previous commit is too far in time; you've resumed work on this project more recently, so the entire time difference shouldn't be used.

The first situation is pretty obvious:

	$ git commit -m "First import [BC]"
	Missing project ID: use git config --add basecamp.project-id your-project-id-here
	[master (root-commit) b6d59fd] First commit [BC]
	 1 files changed, 1 insertions(+), 0 deletions(-)
	 create mode 100644 foo

Notice the first line? (which, on a TTY, appears in red to get your attention)

On a first commit, or when your commit is so remote from the previous one that the time between the two is totally unrelated to your working time, you can just **specify the time**.  Just add a colon (`:`) and the number of minutes you worked on this commit:

	$ git commit -m "First import [BC:15]"
	Logging 0:15h of work…
	Time logged!
	[master (root-commit) b6d59fd] First commit [BC:15]
	 1 files changed, 1 insertions(+), 0 deletions(-)
	 create mode 100644 foo

If you want to specify time in hours, instead of minutes, you can just append a "h" after the amount:

	$ git commit -m "First import [BC:2h]"
	Logging 2:00h of work…
	Time logged!
	[master (root-commit) b6d59fd] First commit [BC:2h]
	 1 files changed, 1 insertions(+), 0 deletions(-)
	 create mode 100644 foo

Note that by default, the script will strip the tag from your commit message by amending the commit you just did (once it successfully logged your time to Basecamp, that is):

	$ git log --oneline -1
	b6d59fd First commit

When you’re working on a nonfirst commit, and most of your time between the previous commit and this one was indeed related to the task at hand, you can specify a negative time, which will be treated as time to _subtract from the actual time difference_.  So, to say "log the entire time since my previous commit, except for 20 minutes," you'd go like this:

	$ git commit -m "Made the animation smoother on iOS [BC:-20]"
	Logging 0:25h of work…
	Time logged!
	[master 4f17db2] Made the animation smoother on iOS [BC:-20]
	 1 files changed, 1 insertions(+), 0 deletions(-)

The hour notation (adding a "h" suffix to the time you specify) works in this situation, too.

Using tasks
-----------

If you're neat and organized, you are careful to use well-defined tasks in your Basecamp project, which you then assign to whatever developer is responsible for them.  Ideally, you then log time _to these tasks_, instead of just generally at the project level.

This script lets you assign your time entry to a specific task.  There are three ways to do this:

* without specifying which task (you then must have one and only one uncompleted task assigned to you in the project)
* specifying a text pattern to match against your assigned uncompleted task names (only one must satisfy the pattern)
* specifying the actual task ID

To assign time to a task, just add ":T" right after the opening "BC" in your tag.  So _before_ any time information you may use.  Here’s an example:

	$ git commit -m "Made the animation smoother on iOS [BC:T]"
	Logging 0:45h of work…
	-> Auto-detected single matching task: UI cleanup for iOS devices (#12345678)
	Time logged to task!
	[master 4f17db2] Made the animation smmother on iOS [BC:T]
	 1 files changed, 1 insertions(+), 0 deletions(-)

Notice the auto-detected-task line.  This is possible here because that task is the _only uncompleted task assigned to me_ on the project I'm logging to.  But what if there are several?

	$ git commit -m "Made the animation smoother on iOS [BC:T]"
	Logging 0:45h of work…
	-> Too many tasks to choose from: either specify the task ID or a set of words to narrow down task descriptions
	 -   12345678 = UI cleanup on iOS devices
	 -   12345699 = UI cleanup on WebOS devices
	Specify a task.
	[master 4f17db2] Made the animation smmother on iOS [BC:T]
	 1 files changed, 1 insertions(+), 0 deletions(-)

Ouch.  Well, at least you can now specify either the task ID or a word filter to narrow things down.  Both appear right after the "T" marker in your Basecamp-logging tag.  The ID variant is simple enough:

	$ git commit -m "Made the animation smoother on iOS [BC:T12345678]"
	Logging 0:45h of work…
	Time logged to task!
	[master 4f17db2] Made the animation smmother on iOS [BC:T12345678]
	 1 files changed, 1 insertions(+), 0 deletions(-)

A word filter is just a series of words (groups of alphanumeric characters).  The system will filter the list of possible tasks, retaining only those with a name that contains _all your words, in no particular order, in a case-insensitive manner.  Most often, a single word, or word fragment, is sufficient.  Not caring about the order of words also spares you from having to know the exact task name.  Here's an example:

	$ git commit -m "Made the animation smoother on iOS [BC:Tios]"
	Logging 0:45h of work…
	-> Auto-detected single matching task: UI cleanup on iOS devices (#12345678)
	Time logged to task!
	[master 4f17db2] Made the animation smmother on iOS [BC:Tios]
	 1 files changed, 1 insertions(+), 0 deletions(-)

If you're working on a fairly long-winded task, you may want to _cache_ the task ID for it, in order to save a couple seconds on every commit by avoiding the tasks lookup.  This is a bit dangerous (forgetting to clear that local Git preference once you're done means you'll be logging to that task by default when using task mode), but it can be done.  Just set `basecamp.current-task-id` in your local Git configuration, and you're ready to roll.  Don't forget to remove it though (using `git config --unset-all basecamp.current-task-id`) once you're done.

Also note that specifying the task ID explicitly in your tag won't look anything up, and also accept logging on tasks officially marked as complete (in case you were a bit bold and eager when marking it as such).

By the way, wouldn't it be nice if you could not only log time to a task, but also _mark it as complete_?  Of course that would.  So you can: just end your task specifier (be it an ID, a word filter, or even nothing because of cached ID or auto-detection) with an equal sign (`=`).  Check this out:

	$ git commit -m "Made the animation smoother on iOS [BC:Tios=]"
	 1 files changed, 1 insertions(+), 0 deletions(-)
	Logging 0:45h of work…
	-> Auto-detected single matching task: UI cleanup on iOS devices (#12345678)
	Time logged to task!
	Task marked as completed!
	[master 4f17db2] Made the animation smmother on iOS [BC:Tios=]

Ain't life good?  By the way, this automagically clears your local task ID cache, if there was any.

Caveats
-------

There are a few caveats you should keep in mind:

* This script is intended for _post-commit_ hooks.  Which means your commit will already have happened by the time the script kicks in, so failure to log time to Basecamp doesn't mean your commit didn't get in.  If you have time-logging issues of any sort, remember your commit already went through, so you'll need to _amend_ it, not to create a new one.
* **Amending commits does not cancel you previous time logging.**  So you'll just be logging double-time.  Watch out for this!  You'll need to update your Basecamp-logging tag to reflect the time you spent amending the commit.
* Conversely, because the script scripts your Basecamp tag from the commit message (at least by default), amending with automatic reuse of the previous message (`git commit --amend -C HEAD`, you know?) (what, you don't?) (tsk…) will not log any additional time (which is better than too much time, I guess).
* Task specifications only accept alphanumeric characters and whitespace.  Using other characters will invalidate your tag and therefore ignore Basecamp logging entirely.

In general, this script works pretty well on the OSX and Ubuntu development machines used by a number of friends and yours truly, across several Basecamp accounts and users.  However, this is open-source and just as you don't owe me anything, I don't _guarantee_ anything.  Still, ping me if in trouble!

Configuration reference
-----------------------

The configuration _per se_ lies in Git configuration, some of it global (that is, at your profile level, working across all your projects), and some of it local (at your repository level, hence per-project).  However, the script does not enforce "globalhood," as you may work on projects using several Basecamp accounts (or, at least, URLs).  So my advice is to set the global config, and if you end up with one or two repos using a different API token or endpoint, override the settings at the repo level.

The Git configuration keys are as follows:

<table>
  <thead>
    <tr>
      <th>Key</th>
      <th>(Intended) scope</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>`basecamp.endpoint`</th>
      <td>Global</td>
      <td>The URL of your Basecamp account; use the proper protocol (`http://`) or (`https://`), depending on your settings.  Using the wrong protocol will break the script!</td>
    </tr>
    <tr>
      <th>`basecamp.api-token`</th>
      <td>Global</td>
      <td>Your personal API token, accessible at the bottom of your _My Info_ page.</td>
    </tr>
    <tr>
      <th>`basecamp.person-id`</th>
      <td>Global</td>
      <td>Your own Basecamp person ID; you don't need to set this explicitly as the script will grab and cache it locally the first time you use it.</td>
    </tr>
    <tr>
      <th>`basecamp.project-id`</th>
      <td>Local</td>
      <td>The Basecamp project ID for the project your repository is about.  You can get it from your project URLs; for instance, your project’s dashboard URL should look something like `https://your.basecamp.url/projects/PROJECT-ID/log`.</td>
    </tr>
    <tr>
      <th>`basecamp.current-task-id`</th>
      <td>Local</td>
      <td>The task you’re currently working on, when logging in task mode (using the `:T` marker in your Basecamp tag at the end of your commit message).  You should seldom need this, and don't forget to clear it once you're done with this task!</td>
    </tr>
  </tbody>
</table>

You can also adjust two bits of script behavior by tweaking two constants in the source code itself (around the top of the `GitBasecampTimerLogger` class):

* `OPT_CACHE_PERSON_ID` determines whether to cache your own Basecamp person ID locally once fetched from Basecamp.  There really is no reason why you would want to waste time _on every commit_ by re-requesting it, but hey, if that makes you happier…  This is enabled by default, obviously.
* `OPT_STRIP_TAG_FROM_COMMIT` amends the commit you just made by stripping the Basecamp-logging tag from it, once said logging was successfully performed.  This is also enabled by default, but perhaps you want to keep these tags (be careful, though: keeping these around _will re-log that time when amending the commit_).

Licence
-------

This is licenced under the MIT licence, listed below and at the top of the script.  The executive summary goes: do whatever you want with it, except strip the copyright or licence info from it.

	# Copyright (c) 2010 Christophe Porteneuve <tdd@git-attitude.fr>
	#
	# Permission is hereby granted, free of charge, to any person obtaining a copy
	# of this software and associated documentation files (the "Software"), to deal
	# in the Software without restriction, including without limitation the rights
	# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	# copies of the Software, and to permit persons to whom the Software is
	# furnished to do so, subject to the following conditions:
	#
	# The above copyright notice and this permission notice shall be included in
	# all copies or substantial portions of the Software.
	#
	# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
	# THE SOFTWARE.

Contributing
------------

People, this is open-source, using plain old Ruby, and it's posted on Github.  Fork away and be merry!

Happy time-logging,

(s.) Christophe