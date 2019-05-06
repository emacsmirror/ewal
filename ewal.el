;;; ewal.el --- A pywal-based theme generator -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Uros Perisic
;; Copyright (C) 2019 Grant Shangreaux
;; Copyright (C) 2016-2018 Henrik Lissner

;; Author: Uros Perisic
;; URL: https://gitlab.com/jjzmajic/ewal.el
;;
;; Version: 0.1
;; Keywords: faces
;; Package-Requires: ((emacs "25"))

;; This program is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation, either version 3 of the License, or (at your option) any later
;; version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; this program. If not, see <http://www.gnu.org/licenses/>.

;; This file is not part of Emacs.

;;; Commentary:

;; This is a color theme generator for Emacs with an eye towards Spacemacs
;; <https://github.com/syl20bnr/spacemacs>, and `spacemacs-theme'
;; <https://github.com/nashamri/spacemacs-theme>, but no dependencies on either,
;; so you can use it to colorize your vanilla Emacs as well.

;; My hope is that `ewal' will remain theme agnostic, with people contributing
;; functions like `ewal-get-spacemacs-theme-colors' for other popular themes
;; such as `solarized-emacs' <https://github.com/bbatsov/solarized-emacs>,
;; making it easy to keep the style of different themes, while adapting them to
;; the rest of your theming setup. No problem should ever have to be solved
;; twice!

;;; Code:

;; deps
(require 'cl-lib)
(require 'color)
(require 'json)
(require 'term/tty-colors)

(defgroup ewal nil
  "ewal options."
  :group 'faces)

(defcustom ewal-wal-cache-dir
  (file-name-as-directory (expand-file-name "~/.cache/wal"))
  "Location of wal cache directory."
  :type 'string
  :group 'ewal)

(defcustom ewal-wal-cache-json-file
  (concat ewal-wal-cache-dir "colors.json")
  "Location of cached wal theme in json format."
  :type 'string
  :group 'ewal)

(defcustom ewal-ansi-color-name-symbols
  (mapcar #'intern
          (cl-loop for (key . _value)
                   in tty-defined-color-alist
                   collect key))
  "The 8 most universaly supported TTY color names.
They will be extracted from `ewal--cache-json-file', and
with the right escape sequences applied using
#+BEGIN_SRC shell
source ${HOME}/.cache/wal/colors-tty.sh
#+END_SRC
should be viewable even in the Linux console (See
https://github.com/dylanaraps/pywal/wiki/Getting-Started#applying-the-theme-to-new-terminals
for more details). NOTE: Order matters."
  :type 'list
  :group 'ewal)

(defcustom ewal-daemon-use-tty-colors nil
  "Whether to use TTY version of `ewal' colors in Emacs daemon.
It's a numbers game. Set to t if you connect to your Emacs server
from a TTY most of the time, unless you want to run `ewal' every
time you connect with `emacsclient'."
  :type 'boolean
  :group 'ewal)

(defcustom ewal-use-tty-colors (if (daemonp)
                                   ewal-daemon-use-tty-colors
                                 (not (display-graphic-p)))
  "Whether to use TTY version of `ewal' colors.
Meant for setting TTY theme regardless of GUI support."
  :type 'boolean
  :group 'ewal)

(defcustom ewal-primary-accent-color 'magenta
  "Predominant `ewal' color.
Must be one of `ewal-ansi-color-name-symbols'"
  :type 'symbol
  :group 'ewal)

(defvar ewal-secondary-accent-color 'blue
  "Second most predominant `ewal' color.
Must be one of `ewal-ansi-color-name-symbols'")

(defvar ewal-base-palette nil
  "Current base palette extracted from `ewal-wal-cache-json-file'.")

(defvar ewal-extended-palette nil
  "Extended palette based on `ewal-base-palette'.")

;; store everything in global variables for easy viewing
;; only set when colors schemes are generated
(defvar ewal-spacemacs-theme-colors nil
  "`spacemacs-theme' compatible colors.
Extracted from current `ewal' theme.")

(defvar ewal-spacemacs-evil-cursors-colors nil
  "`spacemacs-evil-cursors' compatible colors.
Extracted from current `ewal' palette.")

(defvar ewal-emacs-evil-cursors-colors nil
  "Vanilla Emacs Evil compatible colors.
Extracted from current `ewal' palette, and stored in a plist for
easy application.")

(defun ewal--use-tty-colors-p (tty)
  "Utility function to check if TTY colors should be used."
  (if (boundp tty) tty
    (or ewal-use-tty-colors
        (display-graphic-p))))


;;;###autoload
(defun ewal-load-wal-colors (&optional json color-names)
  "Read JSON as the most complete of the cached wal files.
COLOR-NAMES will be associated with the first 8 colors of the
cached wal colors. COLOR-NAMES are meant to be used in
conjunction with `ewal-ansi-color-name-symbols'.
\"Special\" wal colors such as \"background\", \"foreground\",
and \"cursor\", tend to \(but do not always\) correspond to the
remaining colors generated by wal. Add those special colors to
the returned alist. Return nil on failure."
  (condition-case nil
      (let* ((json (or json ewal-wal-cache-json-file))
             (json-object-type 'alist)
             (json-array-type 'list)
             (color-names (or color-names ewal-ansi-color-name-symbols))
             (colors (json-read-file json))
             (special-colors (alist-get 'special colors))
             (regular-colors (alist-get 'colors colors))
             (regular-color-values (cl-loop for (_key . value)
                                            in regular-colors
                                            collect value))
             (cannonical-colors (cl-pairlis color-names regular-color-values)))
        ;; unofficial comment color (always used as such)
        (cl-pushnew (cons 'comment (nth 8 regular-color-values)) special-colors)
        (append special-colors cannonical-colors))
    (error nil)))

;; Color helper functions, shamelessly *borrowed* from solarized
(defun ewal--color-name-to-rgb (color)
  "Retrieves the hex string represented the named COLOR (e.g. \"red\")."
  (cl-loop with div = (float (car (tty-color-standard-values "#ffffff")))
           for x in (tty-color-standard-values (downcase color))
           collect (/ x div)))

(defun ewal--color-blend (color1 color2 alpha)
  "Blend COLOR1 and COLOR2 (hex strings) together by a coefficient ALPHA.
\(a float between 0 and 1\)"
  (when (and color1 color2)
    (cond ((and color1 color2 (symbolp color1) (symbolp color2))
           (ewal--color-blend (ewal--get-color color1 0)
                              (ewal--get-color color2 0) alpha))

          ((or (listp color1) (listp color2))
           (cl-loop for x in color1
                    when (if (listp color2) (pop color2) color2)
                    collect (ewal--color-blend x it alpha)))

          ((and (string-prefix-p "#" color1) (string-prefix-p "#" color2))
           (apply (lambda (r g b) (format "#%02x%02x%02x"
                                          (* r 255) (* g 255) (* b 255)))
                  (cl-loop for it    in (ewal--color-name-to-rgb color1)
                           for other in (ewal--color-name-to-rgb color2)
                           collect (+ (* alpha it) (* other (- 1 alpha))))))

          (t color1))))

(defun ewal--color-darken (color alpha)
  "Darken a COLOR \(a hexidecimal string\) by a coefficient ALPHA.
\(a float between 0 and 1\)."
  (cond ((and color (symbolp color))
         (ewal--color-darken (ewal--get-color color 0) alpha))
        ((listp color)
         (cl-loop for c in color collect (ewal--color-darken c alpha)))
        (t
         (ewal--color-blend color "#000000" (- 1 alpha)))))

(defun ewal--color-lighten (color alpha)
  "Brighten a COLOR (a hexidecimal string) by a coefficient ALPHA.
\(a float between 0 and 1\)."
  (cond ((and color (symbolp color))
         (ewal--color-lighten (ewal--get-color color 0) alpha))
        ((listp color)
         (cl-loop for c in color collect (ewal--color-lighten c alpha)))
        (t
         (ewal--color-blend color "#FFFFFF" (- 1 alpha)))))

(defun ewal--extend-base-color (color num-shades shade-percent-difference)
  "Extend \(darken \(-\) or lighten \(+\)\) COLOR.
Do so by 2 * NUM-SHADES \(NUM-SHADES lighter, and NUM-SHADES
darker\), in increments of SHADE-PERCENT-DIFFERENCE percentage
points. Return list of extended colors"
  (let ((darker-colors
         (cl-loop for i from num-shades downto 1 by 1
                  collect (ewal--color-darken
                          color (/ (* i shade-percent-difference)
                                    (float 100)))))
        (lighter-colors
         (cl-loop for i from 1 upto num-shades by 1
                  collect (ewal--color-lighten
                            color (/ (* i shade-percent-difference)
                                    (float 100))))))
    (append darker-colors (list color) lighter-colors)))

(defun ewal--extend-base-palette (num-shades shade-percent-difference
                                             &optional palette)
  "Use `ewal--extend-base-color' to extend entire base PALETTE.
which defaults to `ewal-base-palette' and returns an extended
palette alist intended to be stored in `ewal-extended-palette'.
Like `ewal--extend-base-color', extend \(darken \(-\) or lighten
\(+\)\) COLOR. Do so by 2 * NUM-SHADES \(NUM-SHADES lighter, and
NUM-SHADES darker\), in increments of SHADE-PERCENT-DIFFERENCE
percentage points. Return list of extended colors"
  (let ((palette (or palette ewal-base-palette)))
    (cl-loop for (key . value)
             in palette
             collect `(,key . ,(ewal--extend-base-color
                                value num-shades shade-percent-difference)))))

(defun ewal--get-color (color &optional shade tty palette)
  "Return SHADE of COLOR from current `ewal' PALETTE.
Choose color that is darker (-) or lightener (+) than COLOR
\(must be one of `ewal-ansi-color-name-symbols'\) by SHADE. SHADE
defaults to 0, returning original wal COLOR. If SHADE exceeds
number of available shades, the darkest/lightest shade is
returned. If TTY is t, return original, TTY compatible `wal'
color regardless od SHADE."
  (let* ((palette (or palette ewal-extended-palette))
         (tty (or tty ewal-use-tty-colors))
         (middle (/ (- (length (car ewal-extended-palette)) 1) 2))
         (shade (or shade 0))
         (original-color (nth middle (alist-get color palette)))
         (requested-color (nth (+ middle shade) (alist-get color palette)))
         (defined-requested-color (if requested-color
                                 requested-color
                               (car (last (alist-get color palette))))))
    (if tty
        original-color
      defined-requested-color)))

(defun ewal--generate-spacemacs-theme-colors (&optional borders)
  "Make theme colorscheme from theme palettes.
If TTY is t, colorscheme is reduced to basic  supported
colors. If BORDERS is t use `ewal-primary-accent-color' for
borders. I prefer to remove them."
  (let* ((primary-accent-color ewal-primary-accent-color)
         (secondary-accent-color ewal-secondary-accent-color)
         (border-color (if borders primary-accent-color 'background))
         (theme-colors
          `((act1          . ,(ewal--get-color 'background -3))
            (act2          . ,(ewal--get-color primary-accent-color 0))
            (base          . ,(ewal--get-color 'foreground 0))
            (base-dim      . ,(ewal--get-color 'foreground -4))
            (bg1           . ,(ewal--get-color 'background 0))
            ;; used to highlight current line
            (bg2           . ,(ewal--get-color 'background -2))
            (bg3           . ,(ewal--get-color 'background -3))
            (bg4           . ,(ewal--get-color 'background -4))
            (border        . ,(ewal--get-color border-color 0))
            (cblk          . ,(ewal--get-color 'foreground -3))
            (cblk-bg       . ,(ewal--get-color 'background -3))
            (cblk-ln       . ,(ewal--get-color primary-accent-color 4))
            (cblk-ln-bg    . ,(ewal--get-color primary-accent-color -4))
            (cursor        . ,(ewal--get-color 'cursor 0))
            (const         . ,(ewal--get-color primary-accent-color 4))
            (comment       . ,(ewal--get-color 'comment 0))
            (comment-bg    . ,(ewal--get-color 'background 0))
            (comp          . ,(ewal--get-color secondary-accent-color 0))
            (err           . ,(ewal--get-color 'red 0))
            (func          . ,(ewal--get-color primary-accent-color 0))
            (head1         . ,(ewal--get-color primary-accent-color 0))
            (head1-bg      . ,(ewal--get-color 'background -3))
            (head2         . ,(ewal--get-color secondary-accent-color 0))
            (head2-bg      . ,(ewal--get-color 'background -3))
            (head3         . ,(ewal--get-color 'cyan 0))
            (head3-bg      . ,(ewal--get-color 'background -3))
            (head4         . ,(ewal--get-color 'yellow 0))
            (head4-bg      . ,(ewal--get-color 'background -3))
            (highlight     . ,(ewal--get-color 'background 4))
            (highlight-dim . ,(ewal--get-color 'background 2))
            (keyword       . ,(ewal--get-color secondary-accent-color 0))
            (lnum          . ,(ewal--get-color 'comment 0))
            (mat           . ,(ewal--get-color 'green 0))
            (meta          . ,(ewal--get-color 'yellow 4))
            (str           . ,(ewal--get-color 'cyan 0))
            (suc           . ,(ewal--get-color 'green 4))
            (ttip          . ,(ewal--get-color 'comment 0))
            ;; same as `bg2'
            (ttip-sl       . ,(ewal--get-color 'background -2))
            (ttip-bg       . ,(ewal--get-color 'background 0))
            (type          . ,(ewal--get-color 'red 2))
            (var           . ,(ewal--get-color secondary-accent-color 4))
            (war           . ,(ewal--get-color 'red 4))
            ;; colors
            (aqua          . ,(ewal--get-color 'cyan 0))
            (aqua-bg       . ,(ewal--get-color 'cyan -3))
            (green         . ,(ewal--get-color 'green 0))
            (green-bg      . ,(ewal--get-color 'green -3))
            (green-bg-s    . ,(ewal--get-color 'green -4))
            ;; literally the same as `aqua' in web development
            (cyan          . ,(ewal--get-color 'cyan 0))
            (red           . ,(ewal--get-color 'red 0))
            (red-bg        . ,(ewal--get-color 'red -3))
            (red-bg-s      . ,(ewal--get-color 'red -4))
            (blue          . ,(ewal--get-color 'blue 0))
            (blue-bg       . ,(ewal--get-color 'blue -3))
            (blue-bg-s     . ,(ewal--get-color 'blue -4))
            (magenta       . ,(ewal--get-color 'magenta 0))
            (yellow        . ,(ewal--get-color 'yellow 0))
            (yellow-bg     . ,(ewal--get-color 'yellow -3)))))
         theme-colors))

(defun ewal--generate-spacemacs-evil-cursors-colors ()
  "Use wal colors to customize `spacemacs-evil-cursors'.
TTY specifies whether to use TTY or GUI colors."
  `(("normal" ,(ewal--get-color 'cursor 0) box)
    ("insert" ,(ewal--get-color 'green 0) (bar . 2))
    ("emacs" ,(ewal--get-color 'blue 0) box)
    ("hybrid" ,(ewal--get-color 'blue 0) (bar . 2))
    ("evilified" ,(ewal--get-color 'red 0) box)
    ("visual" ,(ewal--get-color 'white -4) (hbar . 2))
    ("motion" ,(ewal--get-color ewal-primary-accent-color 0) box)
    ("replace" ,(ewal--get-color 'red -4) (hbar . 2))
    ("lisp" ,(ewal--get-color 'magenta 4) box)
    ("iedit" ,(ewal--get-color 'magenta -4) box)
    ("iedit-insert" ,(ewal--get-color 'magenta -4) (bar . 2))))

(defun ewal--generate-emacs-evil-cursors-colors ()
  "Use wal colors to customize vanilla Emacs Evil cursor colors.
TTY specifies whether to use or GUI colors."
  `((evil-normal-state-cursor (,(ewal--get-color 'cursor 0) box))
    (evil-insert-state-cursor (,(ewal--get-color 'green 0) (bar . 2)))
    (evil-emacs-state-cursor (,(ewal--get-color 'blue 0) box))
    (evil-hybrid-state-cursor (,(ewal--get-color 'blue 0) (bar . 2)))
    (evil-evilified-state-cursor (,(ewal--get-color 'red 0) box))
    (evil-visual-state-cursor (,(ewal--get-color 'white -4) (hbar . 2)))
    (evil-motion-state-cursor (,(ewal--get-color ewal-primary-accent-color 0) box))
    (evil-replace-state-cursor (,(ewal--get-color 'red -4) (hbar . 2)))
    (evil-lisp-state-cursor (,(ewal--get-color 'magenta 4) box))
    (evil-iedit-state-cursor (,(ewal--get-color 'magenta -4) box))
    (evil-iedit-insert-state-cursor (,(ewal--get-color 'magenta -4) (bar . 2)))))

;;;###autoload
(defun ewal-load-ewal-colors (&optional force-reload vars funcs args)
  "Load all relevant `ewal' palettes and colors as environment variables.
Use TTY to determine whether to use TTY colors. Reload
environment variables even if they have already been set if
FORCE-RELOAD is t. Always set `ewal-base-palette' and
`ewal-extended-palette'. Set all extra variables specified in
ordered list VARS, using ordered list FUNCS, applying extra
arguments from nested, ordered list ARGS. VARS, FUNCS, and ARGS
must be of the same length if passed at all."
    (when (or (null ewal-base-palette)
              (null ewal-extended-palette)
              force-reload)
      ;; always set together
      (setq ewal-base-palette (ewal-load-wal-colors)
            ewal-extended-palette (ewal--extend-base-palette 8 5)))
    ;; let errors propagate if only some args are set
    (when (or vars funcs args)
      ;; accept atoms as well as lists
      (let ((vars (if (atom vars) (list vars) vars))
            (funcs (if (atom funcs) (list funcs) funcs))
            (args (if (atom args) (list args) args)))
        (cl-loop for var in vars
                 for func in funcs
                 for arglist in args
                 do (set var (if (atom arglist)
                                 (if (null arglist)
                                     (funcall func)
                                   (funcall func arglist))
                               (apply func arglist))))))
  ewal-extended-palette)


;;;###autoload
(defun ewal-get-color (color &optional shade)
  "Same as `ewal--get-color' but call `ewal-load-ewal-colors' first.
Pass COLOR and SHADE to `ewal--get-color'. Meant to be called
from user config."
  (ewal-load-ewal-colors)
  (ewal--get-color color shade))

;;;###autoload
(cl-defun ewal-get-spacemacs-theme-colors
    (&key apply force-reload borders)
  "Get `spacemacs-theme' colors.
For usage see: <https://github.com/nashamri/spacemacs-theme>. If
APPLY is t, set relevant environment variable for the user.
Reload `ewal' environment variables before returning colors even
if they have already been computed if FORCE-RELOAD is t. TTY
defaults to return value of `ewal--use-tty-colors-p'. if TTY is
t, use TTY colors."
  (ewal-load-ewal-colors force-reload
                         'ewal-spacemacs-theme-colors
                         #'ewal--generate-spacemacs-theme-colors
                         borders)
  (if apply
      (setq spacemacs-theme-custom-colors ewal-spacemacs-theme-colors)
    ewal-spacemacs-theme-colors))

;;;###autoload
(cl-defun ewal-get-spacemacs-evil-cursors-colors
    (&key apply force-reload)
  "Get `spacemacs-evil-cursors' colors.
If APPLY is t, set relevant environment variable for the user.
Reload `ewal' environment variables before returning colors even
if they have already been computed if FORCE-RELOAD is t. TTY
defaults to return value of `ewal--use-tty-colors-p'. If TTY is
t, use TTY colors."
  (ewal-load-ewal-colors force-reload 'ewal-spacemacs-evil-cursors-colors
                         #'ewal--generate-spacemacs-evil-cursors-colors
                         nil)
  (if apply
      (setq spacemacs-evil-cursors ewal-spacemacs-evil-cursors-colors)
    ewal-spacemacs-evil-cursors-colors))

;;;###autoload
(cl-defun ewal-get-emacs-evil-cursors-colors
    (&key apply force-reload)
  "Get vanilla Emacs Evil cursor colors.
If APPLY is t, set relevant environment variables for the user.
Reload `ewal' environment variables before returning colors even
if they have already been computed if FORCE-RELOAD is t. TTY
defaults to return value of `ewal--use-tty-colors-p'. If TTY is
t, use TTY colors."
  (ewal-load-ewal-colors force-reload 'ewal-spacemacs-evil-cursors-colors
                         #'ewal--generate-spacemacs-evil-cursors-colors
                         nil)
  (if apply
      (cl-loop for (key . value)
               in ewal-emacs-evil-cursors-colors
               do (set key value))
    ewal-emacs-evil-cursors-colors))

(provide 'ewal)

;;; ewal.el ends here
