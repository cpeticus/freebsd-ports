------------------------------------------------------------------------------
--                                                                          --
--                 GNU ADA RUNTIME LIBRARY (GNARL) COMPONENTS               --
--                                                                          --
--           S Y S T E M . I N T E R R U P T _ M A N A G E M E N T          --
--                                                                          --
--                                  B o d y                                 --
--                         (Version for new GNARL)                          --
--                                                                          --
--                             $Revision: 1.3 $                            --
--                                                                          --
--   Copyright (C) 1991,1992,1993,1994,1995,1996 Florida State University   --
--                                                                          --
-- GNARL is free software; you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion. GNARL is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNARL; see file COPYING.  If not, write --
-- to  the Free Software Foundation,  59 Temple Place - Suite 330,  Boston, --
-- MA 02111-1307, USA.                                                      --
--                                                                          --
-- As a special exception,  if other files  instantiate  generics from this --
-- unit, or you link  this unit with other files  to produce an executable, --
-- this  unit  does not  by itself cause  the resulting  executable  to  be --
-- covered  by the  GNU  General  Public  License.  This exception does not --
-- however invalidate  any other reasons why  the executable file  might be --
-- covered by the  GNU Public License.                                      --
--                                                                          --
-- GNARL was developed by the GNARL team at Florida State University. It is --
-- now maintained by Ada Core Technologies Inc. in cooperation with Florida --
-- State University (http://www.gnat.com).                                  --
--                                                                          --
------------------------------------------------------------------------------

--  This is the FreeBSD PTHREADS version of this package

--  This is only a first approximation.
--  It should be autogenerated by the m4 macro processor.
--  Contributed by Peter Burwood (gnat@arcangel.dircon.co.uk).

--  This file performs the system-dependent translation between machine
--  exceptions and the Ada exceptions, if any, that should be raised when
--  they occur.  This version works for FreeBSD.  Contributed by
--  Daniel M. Eischen (eischen@vigrid.com).

--  PLEASE DO NOT add any dependences on other packages.
--  This package is designed to work with or without tasking support.

--  See the other warnings in the package specification before making
--  any modifications to this file.

--  Make a careful study of all signals available under the OS,
--  to see which need to be reserved, kept always unmasked,
--  or kept always unmasked.
--  Be on the lookout for special signals that
--  may be used by the thread library.

with Interfaces.C;
--  used for int and other types

with System.OS_Interface;
--  used for various Constants, Signal and types

package body System.Interrupt_Management is

   use Interfaces.C;
   use System.OS_Interface;

   type Interrupt_List is array (Interrupt_ID range <>) of Interrupt_ID;
   Exception_Interrupts : constant Interrupt_List :=
     (SIGFPE, SIGILL, SIGSEGV, SIGBUS);


   ----------------------
   -- Notify_Exception --
   ----------------------

   --  This function identifies the Ada exception to be raised using
   --  the information when the system received a synchronous signal.
   --  Since this function is machine and OS dependent, different code
   --  has to be provided for different target.

   --  Language specs say signal handlers take exactly one arg, even
   --  though FreeBSD actually supplies three.  Ugh!

   procedure Notify_Exception
     (signo   : Signal;
      code    : Interfaces.C.int;
      context : access struct_sigcontext);

   procedure Notify_Exception
     (signo   : Signal;
      code    : Interfaces.C.int;
      context : access struct_sigcontext) is
   begin

      --  As long as we are using a longjmp to return control to the
      --  exception handler on the runtime stack, we are safe. The original
      --  signal mask (the one we had before coming into this signal catching
      --  function) will be restored by the longjmp. Therefore, raising
      --  an exception in this handler should be a safe operation.

      --  Check that treatment of exception propagation here
      --  is consistent with treatment of the abort signal in
      --  System.Task_Primitives.Operations.

      --  ?????
      --  The code below is first approximation.
      --  It would be nice to figure out more
      --  precisely what exception has occurred.
      --  One also should arrange to use an alternate stack for
      --  recovery from stack overflow.
      --  I don't understand the Linux kernel code well
      --  enough to figure out how to do this yet.
      --  I hope someone will look at this.  --Ted Baker

      --  How can SIGSEGV be split into constraint and storage errors ?
      --  What should SIGILL really raise ? Some implemenations have
      --  codes for different types of SIGILL and some raise Storage_Error.
      --  What causes SIGBUS and should it be caught ?
      --  Peter Burwood

      case signo is
         when SIGFPE =>
            raise Constraint_Error;
         when SIGILL =>
            raise Constraint_Error;
         when SIGSEGV =>
            raise Storage_Error;
         when SIGBUS =>
            raise Storage_Error;
         when others =>
            pragma Assert (False);
            null;
      end case;
   end Notify_Exception;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
      act     : aliased struct_sigaction;
      old_act : aliased struct_sigaction;
      mask    : aliased sigset_t;
      Result  : Interfaces.C.int;

      Unreserve_All_Interrupts : Interfaces.C.int;
      pragma Import
        (C, Unreserve_All_Interrupts, "__gl_unreserve_all_interrupts");

   begin

      Abort_Task_Interrupt := SIGABRT;
      --  Change this if you want to use another signal for task abort.
      --  SIGTERM might be a good one.

      act.sa_handler := Notify_Exception'Address;

      act.sa_flags := 16#010#;
      --  Set sa_flags to SA_NODEFER so that during the handler execution
      --  we do not change the Signal_Mask to be masked for the Signal.
      --  This is a temporary fix to the problem that the Signal_Mask is
      --  not restored after the exception (longjmp) from the handler.
      --  The right fix should be made in sigsetjmp so that we save
      --  the Signal_Set and restore it after a longjmp.
      --  In that case, this field should be changed back to 0. ??? (Dong-Ik)

      Result := sigemptyset (mask'Access);
      pragma Assert (Result = 0);

      --  ??? For the same reason explained above, we can't mask these
      --  signals because otherwise we won't be able to catch more than
      --  one signal.

      --  for I in Exception_Interrupts'Range loop
      --     Result :=
      --       sigaddset (mask'Access, Signal (Exception_Interrupts (I)));
      --     pragma Assert (Result = 0);
      --  end loop;

      act.sa_mask := mask;

      for I in Exception_Interrupts'Range loop
         Keep_Unmasked (Exception_Interrupts (I)) := True;
         Result :=
           sigaction
             (Signal (Exception_Interrupts (I)), act'Unchecked_Access,
              old_act'Unchecked_Access);
         pragma Assert (Result = 0);
      end loop;

      Keep_Unmasked (Abort_Task_Interrupt) := True;
      Keep_Unmasked (SIGSTOP) := True;
      Keep_Unmasked (SIGKILL) := True;

      --  By keeping SIGINT unmasked, allow the user to do a Ctrl-C, but in the
      --  same time, disable the ability of handling this signal
      --  via Ada.Interrupts.
      --  The pragma Unreserve_All_Interrupts let the user the ability to
      --  change this behavior.

      if Unreserve_All_Interrupts = 0 then
         Keep_Unmasked (SIGINT) := True;
      else
         Keep_Unmasked (SIGINT)  := False;
      end if;

      --  FreeBSD uses SIGINFO to dump thread status to stdout.  If
      --  the user really wants to attach his own handler, let him.

      --  FreeBSD pthreads uses setitimer/getitimer for thread scheduling.
      --  It's not clear, but it looks as if it only needs SIGVTALRM
      --  in order to handle the setitimer/getitimer operations.  We
      --  could probably allow SIGALARM, but we'll leave it as unmasked
      --  for now.  FreeBSD pthreads also needs SIGCHLD.
      Keep_Unmasked (SIGCHLD) := True;
      Keep_Unmasked (SIGALRM) := True;
      Keep_Unmasked (SIGVTALRM) := True;

      Reserve := Reserve or Keep_Unmasked or Keep_Masked;

      Reserve (0) := true;
      --  We do not have Signal 0 in reality. We just use this value
      --  to identify non-existent signals (see s-intnam.ads). Therefore,
      --  Signal 0 should not be used in all signal related operations hence
      --  mark it as reserved.

   end Initialize;

begin
   Initialize;
end System.Interrupt_Management;
