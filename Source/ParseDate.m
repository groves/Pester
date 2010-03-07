//
//  ParseDate.m
//  Pester
//
//  Created by Nicholas Riley on 11/28/07.
//  Copyright 2007 Nicholas Riley. All rights reserved.
//

#import <Foundation/Foundation.h>

// generated by perl -MExtUtils::Embed -e xsinit -- -o perlxsi.c
#include <EXTERN.h>
#include <perl.h>

EXTERN_C void xs_init (pTHX);

EXTERN_C void boot_DynaLoader (pTHX_ CV* cv);

EXTERN_C void
xs_init(pTHX)
{
    char *file = __FILE__;
    dXSUB_SYS;
    
    /* DynaLoader is a special case */
    newXS("DynaLoader::boot_DynaLoader", boot_DynaLoader, file);
}
// end generated code

static PerlInterpreter *my_perl;
static NSDateFormatter *dateManipFormatter;

NSDate *parse_natural_language_date(NSString *input) {
    if (my_perl == NULL)
	return [NSDate distantPast];

    if (input == nil)
	return nil;

    if ([input rangeOfString: @"|"].length > 0) {
	NSMutableString *sanitized = [[input mutableCopy] autorelease];
	[sanitized replaceOccurrencesOfString: @"|" withString: @""
				      options: NSLiteralSearch
					range: NSMakeRange(0, [sanitized length])];
	input = sanitized;
    }
    
    NSString *temp = [[NSString alloc] initWithFormat: @"my $s = eval {UnixDate(q|%@|, '%%q')}; warn $@ if $@; $s", input];
    // NSLog(@"%@", temp);
    SV *d = eval_pv([temp UTF8String], FALSE);
    [temp release];
    if (d == NULL) return nil;
    
    STRLEN s_len;
    char *s = SvPV(d, s_len);
    if (s == NULL || s_len == 0) return nil;
    
    NSDate *date = [dateManipFormatter dateFromString: [NSString stringWithUTF8String: s]];
    // NSLog(@"%@", date);
    
    return date;
}

// Perl breaks backwards compatibility between 5.8.8 and 5.8.9.
// (libperl.dylib does not contain Perl_sys_init or Perl_sys_term.)
// Use the 5.8.8 definitions, which still seems to work fine with 5.8.9.
// This allows ParseDate to be compiled on 10.6 for 10.5.
#undef PERL_SYS_INIT
#define PERL_SYS_INIT(c,v) MALLOC_CHECK_TAINT2(*c,*v) PERL_FPU_INIT MALLOC_INIT
#undef PERL_SYS_TERM
#define PERL_SYS_TERM() OP_REFCNT_TERM; MALLOC_TERM

static void init_perl(void) {
    const char *argv[] = {"", "-CSD", "-I", "", "-MDate::Manip", "-e", "0"};
    argv[3] = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
    PERL_SYS_INIT(0, NULL);
    my_perl = perl_alloc();
    if (my_perl == NULL) return;
    
    perl_construct(my_perl);
    if (perl_parse(my_perl, xs_init, 7, (char **)argv, NULL) != 0) goto fail;
    
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;
    if (perl_run(my_perl) != 0) goto fail;
    
    // XXX detect localization & time zone/DST changes
    int gmtOffsetMinutes = ([[NSTimeZone defaultTimeZone] secondsFromGMT]) / 60;
    NSString *temp = [[NSString alloc] initWithFormat: @"Date_Init(\"Language=English\", \"DateFormat=non-US\", \"Internal=1\", \"TZ=%c%02d:%02d\")", gmtOffsetMinutes < 0 ? '-' : '+', abs(gmtOffsetMinutes) / 60, abs(gmtOffsetMinutes) % 60];
    SV *d = eval_pv([temp UTF8String], FALSE);
    [temp release];
    if (d == NULL) goto fail;
    
    if (parse_natural_language_date(@"tomorrow") == nil) goto fail;
    
    return;
    
fail:
    perl_destruct(my_perl);
    perl_free(my_perl);
    PERL_SYS_TERM();
    my_perl = NULL;
}


// note: the documentation is misleading here, and this works.
// <http://gcc.gnu.org/ml/gcc-patches/2004-06/msg00385.html>
void initialize(void) __attribute__((constructor));

void initialize(void) {
    dateManipFormatter = [[NSDateFormatter alloc] init];
    [dateManipFormatter setDateFormat: @"yyyyMMddHHmmss"]; // Date::Manip's "%q"
    init_perl();
}