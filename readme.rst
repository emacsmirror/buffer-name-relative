
#####################
Relative Buffer Names
#####################

A minimal minor-mode that sets project relative paths for buffer names
with optional path abbreviation.

Available via `melpa <https://melpa.org/#/buffer-name-relative>`__.


Motivation
==========

To be able to easily identify buffer names where similar named files exist within a project.

.. figure:: https://codeberg.org/attachments/324d3daa-3b7e-4ebb-8884-84605adc9d96
   :scale: 50 %
   :align: center

   Before.

.. figure:: https://codeberg.org/attachments/abcd390e-44c8-461b-84ab-5fbe3dc91e84
   :scale: 50 %
   :align: center

   After.


Usage
=====

Run ``(buffer-name-relative-mode)`` before files are loaded for buffers to load with project-root relative names.

By default, detecting the root uses version control, falling back to the ``default-directory``.

As path names may be quite long (depending on the project), you may wish to abbreviate paths,
see: ``buffer-name-relative-abbrev-limit``.


Customization
-------------

``buffer-name-relative-prefix``: ``"./"``
   The prefix added before the relative path.

``buffer-name-relative-root-functions``: ``(list 'buffer-name-relative-root-path-from-vc)``
   A list of functions that take a file-path and return a string or nil.
   The root directory used will be the first of these function to return a non-nil string.

   Any errors calling these functions are demoted to messages.

   Available functions:

   - ``buffer-name-relative-root-path-from-ffip``
   - ``buffer-name-relative-root-path-from-projectile``
   - ``buffer-name-relative-root-path-from-vc`` (default).

``buffer-name-relative-abbrev-limit``: 0
   When non-zero, abbreviate leading directories to fit within the length
   *(typically values between 1-100).*

   Try setting ``buffer-name-relative-abbrev-limit`` to 16 for example.

   :Before: ``./scripts/presets/keyconfig/keymap_data/keymap_default.py``
   :After: ``./s/p/k/keymap_d~/keymap_default.py``

``buffer-name-relative-fallback``: ``'default``
   The directory to use when a project root is not found, valid options:

   ``'default``
      Name relative to the buffers ``default-directory``.
   ``'absolute``
      Name the buffer based on the absolute path.
   ``nil``
      Don't customize the buffer name when a directory can't be found.


Installation
============

.. code-block:: elisp

   (use-package buffer-name-relative)
   (buffer-name-relative-mode)
