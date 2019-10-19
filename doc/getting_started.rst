***************
Getting Started
***************

.. contents:: Contents
   :local:


Documentation
-------------
For an introduction to Eelbrain, see :ref:`exa-intro` and the other
:ref:`examples`.
For details on each functionality see the API :ref:`reference`.


MacOS: Framework Build
----------------------

On macOS, the GUI tool Eelbrain uses requires a special build of Python called
a "Framework build". You might see this error when trying to create a plot::

    SystemExit: This program needs access to the screen.
    Please run with a Framework build of python, and only when you are
    logged in on the main display of your Mac.

In order to avoid this, Eelbrain installs a shortcut to start `IPython
<ipython.readthedocs.io>`_ with a Framework build::

    $ eelbrain

This automatically launches IPython with the "eelbrain" profile. A default
startup script that executes ``from eelbrain import *`` is created, and can be
changed in the corresponding `IPython profile <http://ipython.readthedocs.io/
en/stable/interactive/tutorial.html?highlight=startup#startup-files>`_.


Quitting iPython
----------------

Sometimes iPython seems to get stuck after this line::

	Do you really want to exit ([y]/n)? y

In those instances, pressing ctrl-c usually terminates iPython immediately.


Windows: Scrolling
------------------

Scrolling inside a plot axes normally uses arrow keys, but this is currently
not possible on Windows (due to an issue in Matplotlib). Instead, the following
keys can be used:

+--------+--------+--------+
|        | ↑ ``i``|        |
+--------+--------+--------+
| ← ``j``|        | → ``l``|
+--------+--------+--------+
|        | ↓ ``k``|        |
+--------+--------+--------+
