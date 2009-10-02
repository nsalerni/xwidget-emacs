/* What the SPP replace file would looklike with MACROS replaced.
 */

/* TEST: The EMU keyword doesn't screw up the function defn. */
char parse_around_emu ()
{
}

/* TEST: A simple word can be replaced in a definition. */
float returnanfloat()
{
}

/* TEST: Punctuation an be replaced in a definition. */
int foo::bar ()
{
}

/* TEST: Multiple lexical characters in a definition */
int mysuper::baz ()
{
}

/* TEST: Macro replacement. */
int increment (int in) {
  return in+1;
}

/* TEST: Macro replacement with complex args */
int myFcn1 ();

int myFcn2 (int a, int b);
int myFcn3 (int a, int b);

/* TEST: Multiple args to a macro. */
struct ma_struct { int moose; int penguin; int emu; };

/* TEST: Macro w/ args, but no body. */

/* TEST: Not a macro with args, but close. */
int not_with_args_fcn (moose)
{
}

/* TEST: macro w/ continuation. */
int continuation_symbol () { };

/* TEST: macros in a macro - tail processing */

int tail (int q) {}

/* TEST: macros used impropertly. */

int tail_fcn(int q);

/* TEST: feature of CPP from LSD <lsdsgster@...> */

int __gthrw_foo (int arg1) { }

/* TEST: macros using macros */
int foo;

/* TEST: macros with args using macros */
int noodle(int noodle);

/* TEST: Double macro using the argument stack. */
int that_foo(int i);
int this_foo(int i);

/* TEST: The G++ namespace macro hack.  Not really part of SPP. */
namespace baz {

  int bazfnc(int b) { }

}

namespace foo { namespace bar {

    int foo_bar_func(int a) { }

  } 
}

/* TEST: The VC++ macro hack. */
namespace std {

  int inside_std_namespace(int a) { }

}

/* TEST: Recursion prevention.  CPP doesn't allow even 1 level of recursion. */
int MACROA () {

}


/* End */

/* arch-tag: fbc5621d-769c-45d0-b924-6c56743189e5
   (do not change this comment) */
