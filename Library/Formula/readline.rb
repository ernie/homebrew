require 'formula'

class Readline < Formula
  homepage 'http://tiswww.case.edu/php/chet/readline/rltop.html'
  url 'http://ftpmirror.gnu.org/readline/readline-6.2.tar.gz'
  mirror 'http://ftp.gnu.org/gnu/readline/readline-6.2.tar.gz'
  sha256 '79a696070a058c233c72dd6ac697021cc64abd5ed51e59db867d66d196a89381'
  version '6.2.4'

  bottle do
    cellar :any
    revision 2
    sha1 'cce49ed4db5ae8065e40468bc8747042f41ed266' => :mavericks
    sha1 'fea45780c788a92108f7ca2d9296dca0c3498579' => :mountain_lion
    sha1 'b4aada7512f8b19eb120c0550cb793b48e8b7057' => :lion
  end

  keg_only <<-EOS
OS X provides the BSD libedit library, which shadows libreadline.
In order to prevent conflicts when programs look for libreadline we are
defaulting this GNU Readline installation to keg-only.
EOS

  # Vendor the patches.
  # The mirrors are unreliable for getting the patches, and the more patches
  # there are, the more unreliable they get. Pulling this patch inline to
  # reduce bug reports.
  # Upstream patches can be found in:
  # http://ftpmirror.gnu.org/readline/readline-6.2-patches
  #
  # We are carrying an additional patch to add Darwin 13 as a build target.
  # Presumably when 10.9 comes out this patch will move upstream.
  # https://github.com/Homebrew/homebrew/pull/21625
  def patches; DATA; end

  def install
    # Always build universal, per https://github.com/Homebrew/homebrew/issues/issue/899
    ENV.universal_binary
    system "./configure", "--prefix=#{prefix}",
                          "--mandir=#{man}",
                          "--infodir=#{info}",
                          "--enable-multibyte"
    system "make install"
  end
end

__END__
diff --git a/callback.c b/callback.c
index 4ee6361..7682cd0 100644
--- a/callback.c
+++ b/callback.c
@@ -148,6 +148,9 @@ rl_callback_read_char ()
 	  eof = _rl_vi_domove_callback (_rl_vimvcxt);
 	  /* Should handle everything, including cleanup, numeric arguments,
 	     and turning off RL_STATE_VIMOTION */
+	  if (RL_ISSTATE (RL_STATE_NUMERICARG) == 0)
+	    _rl_internal_char_cleanup ();
+
 	  return;
 	}
 #endif
diff --git a/input.c b/input.c
index 7c74c99..b49af88 100644
--- a/input.c
+++ b/input.c
@@ -409,7 +409,7 @@ rl_clear_pending_input ()
 int
 rl_read_key ()
 {
-  int c;
+  int c, r;
 
   rl_key_sequence_length++;
 
@@ -429,14 +429,18 @@ rl_read_key ()
 	{
 	  while (rl_event_hook)
 	    {
-	      if (rl_gather_tyi () < 0)	/* XXX - EIO */
+	      if (rl_get_char (&c) != 0)
+		break;
+		
+	      if ((r = rl_gather_tyi ()) < 0)	/* XXX - EIO */
 		{
 		  rl_done = 1;
 		  return ('\n');
 		}
+	      else if (r == 1)			/* read something */
+		continue;
+
 	      RL_CHECK_SIGNALS ();
-	      if (rl_get_char (&c) != 0)
-		break;
 	      if (rl_done)		/* XXX - experimental */
 		return ('\n');
 	      (*rl_event_hook) ();
diff --git a/patchlevel b/patchlevel
index fdf4740..626a945 100644
--- a/patchlevel
+++ b/patchlevel
@@ -1,3 +1,3 @@
 # Do not edit -- exists only for use by patch
 
-1
+4
diff --git a/support/shobj-conf b/support/shobj-conf
index 5a63e80..c61dc78 100644
--- a/support/shobj-conf
+++ b/support/shobj-conf
@@ -157,7 +157,7 @@ freebsd[4-9]*|freebsdelf*|dragonfly*)
 	;;
 
 # Darwin/MacOS X
-darwin[89]*|darwin10*)
+darwin[89]*|darwin1[0123]*)
 	SHOBJ_STATUS=supported
 	SHLIB_STATUS=supported
 	
@@ -186,7 +186,7 @@ darwin*|macosx*)
 	SHLIB_LIBSUFF='dylib'
 
 	case "${host_os}" in
-	darwin[789]*|darwin10*)	SHOBJ_LDFLAGS=''
+	darwin[789]*|darwin1[0123]*)	SHOBJ_LDFLAGS=''
 			SHLIB_XLDFLAGS='-dynamiclib -arch_only `/usr/bin/arch` -install_name $(libdir)/$@ -current_version $(SHLIB_MAJOR)$(SHLIB_MINOR) -compatibility_version $(SHLIB_MAJOR) -v'
 			;;
 	*)		SHOBJ_LDFLAGS='-dynamic'
diff --git a/vi_mode.c b/vi_mode.c
index 41e1dbb..4408053 100644
--- a/vi_mode.c
+++ b/vi_mode.c
@@ -1114,7 +1114,7 @@ rl_domove_read_callback (m)
       rl_beg_of_line (1, c);
       _rl_vi_last_motion = c;
       RL_UNSETSTATE (RL_STATE_VIMOTION);
-      return (0);
+      return (vidomove_dispatch (m));
     }
 #if defined (READLINE_CALLBACKS)
   /* XXX - these need to handle rl_universal_argument bindings */
@@ -1234,11 +1234,19 @@ rl_vi_delete_to (count, key)
       _rl_vimvcxt->motion = '$';
       r = rl_domove_motion_callback (_rl_vimvcxt);
     }
-  else if (vi_redoing)
+  else if (vi_redoing && _rl_vi_last_motion != 'd')	/* `dd' is special */
     {
       _rl_vimvcxt->motion = _rl_vi_last_motion;
       r = rl_domove_motion_callback (_rl_vimvcxt);
     }
+  else if (vi_redoing)		/* handle redoing `dd' here */
+    {
+      _rl_vimvcxt->motion = _rl_vi_last_motion;
+      rl_mark = rl_end;
+      rl_beg_of_line (1, key);
+      RL_UNSETSTATE (RL_STATE_VIMOTION);
+      r = vidomove_dispatch (_rl_vimvcxt);
+    }
 #if defined (READLINE_CALLBACKS)
   else if (RL_ISSTATE (RL_STATE_CALLBACK))
     {
@@ -1316,11 +1324,19 @@ rl_vi_change_to (count, key)
       _rl_vimvcxt->motion = '$';
       r = rl_domove_motion_callback (_rl_vimvcxt);
     }
-  else if (vi_redoing)
+  else if (vi_redoing && _rl_vi_last_motion != 'c')	/* `cc' is special */
     {
       _rl_vimvcxt->motion = _rl_vi_last_motion;
       r = rl_domove_motion_callback (_rl_vimvcxt);
     }
+  else if (vi_redoing)		/* handle redoing `cc' here */
+    {
+      _rl_vimvcxt->motion = _rl_vi_last_motion;
+      rl_mark = rl_end;
+      rl_beg_of_line (1, key);
+      RL_UNSETSTATE (RL_STATE_VIMOTION);
+      r = vidomove_dispatch (_rl_vimvcxt);
+    }
 #if defined (READLINE_CALLBACKS)
   else if (RL_ISSTATE (RL_STATE_CALLBACK))
     {
@@ -1377,6 +1393,19 @@ rl_vi_yank_to (count, key)
       _rl_vimvcxt->motion = '$';
       r = rl_domove_motion_callback (_rl_vimvcxt);
     }
+  else if (vi_redoing && _rl_vi_last_motion != 'y')	/* `yy' is special */
+    {
+      _rl_vimvcxt->motion = _rl_vi_last_motion;
+      r = rl_domove_motion_callback (_rl_vimvcxt);
+    }
+  else if (vi_redoing)			/* handle redoing `yy' here */
+    {
+      _rl_vimvcxt->motion = _rl_vi_last_motion;
+      rl_mark = rl_end;
+      rl_beg_of_line (1, key);
+      RL_UNSETSTATE (RL_STATE_VIMOTION);
+      r = vidomove_dispatch (_rl_vimvcxt);
+    }
 #if defined (READLINE_CALLBACKS)
   else if (RL_ISSTATE (RL_STATE_CALLBACK))
     {
diff --git a/bind.c b/bind.c
index 59e7964..1217a6b 100644
--- a/bind.c
+++ b/bind.c
@@ -1511,6 +1511,9 @@ static int sv_editmode PARAMS((const char *));
 static int sv_histsize PARAMS((const char *));
 static int sv_isrchterm PARAMS((const char *));
 static int sv_keymap PARAMS((const char *));
+static int sv_vi_insert_prompt PARAMS((const char *));
+static int sv_vi_command_prompt PARAMS((const char *));
+static int sv_vi_mode_changed_bin PARAMS((const char *));
 
 static const struct {
   const char * const name;
@@ -1526,6 +1529,9 @@ static const struct {
   { "history-size",	V_INT,		sv_histsize },
   { "isearch-terminators", V_STRING,	sv_isrchterm },
   { "keymap",		V_STRING,	sv_keymap },
+  { "vi-insert-prompt", V_STRING,	sv_vi_insert_prompt },
+  { "vi-command-prompt", V_STRING,	sv_vi_command_prompt },
+  { "vi-mode-changed-bin", V_STRING,	sv_vi_mode_changed_bin },
   { (char *)NULL,	0, (_rl_sv_func_t *)0 }
 };
 
@@ -1711,6 +1717,30 @@ sv_keymap (value)
 }
 
 static int
+sv_vi_insert_prompt (value)
+    const char *value;
+{
+  _rl_set_vi_insert_prompt (value);
+  return 0;
+}
+
+static int
+sv_vi_command_prompt (value)
+    const char *value;
+{
+  _rl_set_vi_command_prompt (value);
+  return 0;
+}
+
+static int
+sv_vi_mode_changed_bin (value)
+    const char *value;
+{
+  _rl_set_vi_mode_changed_bin (value);
+  return 0;
+}
+
+static int
 sv_bell_style (value)
      const char *value;
 {
diff --git a/rlprivate.h b/rlprivate.h
index 384ff67..76baf8f 100644
--- a/rlprivate.h
+++ b/rlprivate.h
@@ -387,6 +387,9 @@ extern int (_rl_to_upper) PARAMS((int));
 extern int (_rl_digit_value) PARAMS((int));
 
 /* vi_mode.c */
+extern void _rl_set_vi_insert_prompt PARAMS((const char *));
+extern void _rl_set_vi_command_prompt PARAMS((const char *));
+extern void _rl_set_vi_mode_changed_bin PARAMS((const char *));
 extern void _rl_vi_initialize_line PARAMS((void));
 extern void _rl_vi_reset_last PARAMS((void));
 extern void _rl_vi_set_last PARAMS((int, int, int));
diff --git a/vi_mode.c b/vi_mode.c
index 4408053..fc0bb98 100644
--- a/vi_mode.c
+++ b/vi_mode.c
@@ -49,6 +49,8 @@
 
 #include <stdio.h>
 
+#include <fcntl.h>
+
 /* Some standard library routines. */
 #include "rldefs.h"
 #include "rlmbutil.h"
@@ -140,16 +142,121 @@ static int vi_yank_dispatch PARAMS((_rl_vimotion_cxt *));
 
 static int vidomove_dispatch PARAMS((_rl_vimotion_cxt *));
 
+#define _RL_PROMPT_INITIAL_SIZE 512
+#define _VI_MODE_PROMPT_FORMAT_SIZE 512
+#define _VI_MODE_PROMPT_SIZE _RL_PROMPT_INITIAL_SIZE + _VI_MODE_PROMPT_FORMAT_SIZE
+static char _rl_prompt_initial[_RL_PROMPT_INITIAL_SIZE] = "\0";
+static char *_rl_prompt_initial_last_line;
+static char _rl_vi_insert_prompt[_VI_MODE_PROMPT_FORMAT_SIZE] = "\0";
+static char _rl_vi_command_prompt[_VI_MODE_PROMPT_FORMAT_SIZE] = "\0";
+#define _VI_MODE_CHANGED_BIN_SIZE 256
+static char _rl_vi_mode_changed_bin[_VI_MODE_CHANGED_BIN_SIZE] = "\0";
+
+void _rl_set_vi_insert_prompt PARAMS((const char *));
+void _rl_set_vi_command_prompt PARAMS((const char *));
+void _rl_set_vi_mode_changed_bin PARAMS((const char *));
+
+static void vi_mode_changed_prompt PARAMS((void));
+static void vi_mode_changed_bin PARAMS((void));
+static void vi_mode_changed PARAMS((void));
+
+static char *
+safe_strncpy (dest, src, n)
+    char *dest;
+    const char *src;
+    int n;
+{
+  if (src) {
+    strncpy (dest, src, n);
+    dest[n - 1] = '\0';
+  }
+  else {
+    dest[0] = '\0';
+  }
+  return dest;
+}
+
+static char *
+parse_prompt_format_escapes (src)
+    char *src;
+{
+  char *r, *w, c, o;
+  static char buf[4] = "000";
+
+  r = src;
+  w = r;
+  while (*r) {
+    c = *r;
+    if (c == '\\') {
+      r++;
+      if (*r == '\\') {
+        c = '\\';
+      }
+      else if (*r == '0') {
+        c = *r;
+        buf[1] = *(r + 1);
+        buf[2] = *(r + 2);
+        o = strtol (buf, NULL, 8);
+        if (o > 0) {
+          r += 2;
+          c = o;
+        }
+      }
+    }
+    r++;
+    if (c > 0) {
+      *w = c;
+      w++;
+    }
+  }
+  *w = '\0';
+  return src;
+}
+
+void
+_rl_set_vi_insert_prompt (value)
+    const char *value;
+{
+  safe_strncpy (_rl_vi_insert_prompt, value, _VI_MODE_PROMPT_FORMAT_SIZE);
+  parse_prompt_format_escapes (_rl_vi_insert_prompt);
+}
+
+void
+_rl_set_vi_command_prompt (value)
+    const char *value;
+{
+  safe_strncpy (_rl_vi_command_prompt, value, _VI_MODE_PROMPT_FORMAT_SIZE);
+  parse_prompt_format_escapes (_rl_vi_command_prompt);
+}
+
+void
+_rl_set_vi_mode_changed_bin (value)
+    const char *value;
+{
+  safe_strncpy (_rl_vi_mode_changed_bin, value, _VI_MODE_CHANGED_BIN_SIZE);
+}
+
 void
 _rl_vi_initialize_line ()
 {
   register int i, n;
+  char *p;
 
   n = sizeof (vi_mark_chars) / sizeof (vi_mark_chars[0]);
   for (i = 0; i < n; i++)
     vi_mark_chars[i] = -1;
 
   RL_UNSETSTATE(RL_STATE_VICMDONCE);
+
+  safe_strncpy (_rl_prompt_initial, rl_prompt, _RL_PROMPT_INITIAL_SIZE);
+  p = strrchr (_rl_prompt_initial, '\n');
+  if (p) {
+      p++;
+  }
+  else {
+    p = _rl_prompt_initial;
+  }
+  _rl_prompt_initial_last_line = p;
 }
 
 void
@@ -671,6 +778,86 @@ rl_vi_eof_maybe (count, c)
 
 /* Insertion mode stuff. */
 
+/* This is meant to be called after vi mode changes. */
+static void
+vi_mode_changed_prompt ()
+{
+  char *prompt, *p;
+  char pattern[] = "{}";
+  static char buf[_VI_MODE_PROMPT_SIZE];
+  int i, j;
+
+  if (VI_INSERT_MODE()) {
+    prompt = _rl_vi_insert_prompt;
+  }
+  else if (VI_COMMAND_MODE()) {
+    prompt = _rl_vi_command_prompt;
+  }
+  if (strlen (prompt)) {
+    i = _rl_prompt_initial_last_line - _rl_prompt_initial;
+    memcpy (buf, _rl_prompt_initial, i);
+    buf[i] = '\0';
+    p = strstr (prompt, pattern);
+    if (p) {
+      j = p - prompt;
+      memcpy (buf + i, prompt, j);
+      buf[i + j] = '\0';
+      strcat (buf, _rl_prompt_initial_last_line);
+      strcat (buf, p + strlen (pattern));
+    }
+    else {
+      strcat (buf, prompt);
+    }
+    prompt = buf;
+  }
+  else {
+    prompt = _rl_prompt_initial;
+  }
+  rl_set_prompt (prompt);
+  _rl_redisplay_after_sigwinch ();
+}
+
+static void
+vi_mode_changed_bin ()
+{
+  pid_t pid;
+  int status, fd_devnull;
+  char *bin = _rl_vi_mode_changed_bin;
+
+  if (!strlen (bin)) {
+    return;
+  }
+  pid = fork ();
+  if (pid < 0) {
+    perror ("vi_mode_changed_bin: fork failed");
+    return;
+  }
+  else if (pid == 0) {
+    close (STDIN_FILENO);
+    fd_devnull = open ("/dev/null", O_RDONLY);
+    dup2 (fd_devnull, STDIN_FILENO);
+    if (VI_INSERT_MODE()) {
+      execl (bin, bin, "insert", NULL);
+    }
+    else if (VI_COMMAND_MODE()) {
+      execl (bin, bin, "command", NULL);
+    }
+    perror ("vi_mode_changed_bin: execv failed");
+    exit (1);
+  }
+  waitpid (pid, &status, 0);
+}
+
+static void
+vi_mode_changed ()
+{
+  if (!isatty (STDIN_FILENO) || !isatty (STDOUT_FILENO)) {
+    return;
+  }
+  vi_mode_changed_prompt ();
+  vi_mode_changed_bin ();
+}
+
 /* Switching from one mode to the other really just involves
    switching keymaps. */
 int
@@ -679,6 +866,9 @@ rl_vi_insertion_mode (count, key)
 {
   _rl_keymap = vi_insertion_keymap;
   _rl_vi_last_key_before_insert = key;
+
+  vi_mode_changed ();
+
   return (0);
 }
 
@@ -763,6 +953,9 @@ rl_vi_movement_mode (count, key)
     rl_free_undo_list ();
 
   RL_SETSTATE (RL_STATE_VICMDONCE);
+
+  vi_mode_changed ();
+
   return (0);
 }
 
       
