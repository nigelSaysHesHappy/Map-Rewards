#if defined _STR_PLUS
 #endinput
#endif
#define _STR_PLUS

// StrPlus - Added String functionality, based loosely off C++ STL strings.
// Written by nigel (NIGathan)
// Version 0.005

// Copies a sub string of source to dest starting at pos and extending len
//   characters.
// If len is not provided, -1, or larger than the length of source, then all
//   characters after pos are copied.
// Returns the size of the copied sub string, which may differ from len
//   depending on size constraints.
// Uses strlen internally, so characters after a null terminator are ignored.
// Always reserves one character for the null terminator, so if len is larger
//   than the size of dest, the substring will be trimmed.
stock SubStr(const String:source[], String:dest[], destSize, pos, len = -1)
{
    new srcLen = strlen(source);
    if (len == 0)
    {
        dest = "";
        return 0;
    }
    if (pos >= srcLen)
    {
        dest = "";
        return -1;
    }
    if ((len < 0) || ((srcLen-pos) < len))
        len = srcLen-pos;
    if (len >= destSize)
        len = destSize-1;
    new end = pos+len;
    for (new i = 0;pos < end;pos++)
        dest[i++] = source[pos]
    dest[end] = '\0';
    return len;
}

// Returns the index in source where search is found or -1 if not found.
// If pos is set, characters in source before pos will be ignored.
stock StrFind(const String:source[], const String:search[], pos = 0)
{
    new srcLen = strlen(source);
    new schLen = strlen(search);
    if (pos >= srcLen)
        return -1;
    new i, j;
    new bool:match = false;
    for (i = pos;((i < srcLen) && (!match));i++)
    {
        for (j = 0;j < schLen;j++)
            if (source[i+j] != search[j])
                break;
        if (j == schLen)
        {
            match = true;
            break;
        }
    }
    if (match)
        return i;
    return -1;
}

// Inserts insert into str at pos.
// If strSize is not big enough to hold everything, insert takes priority.
// If pos+insert is longer than strSize, insert will be trimmed.
// One character is always reserved for the null terminator.
// 
// Returns 0 on success or 1 on error.
stock StrInsert(String:str[], strSize, const String:insert[], pos)
{
    new strLen = strlen(str);
    new insLen = strlen(insert);
    if ((pos < 0) || (pos >= strLen))
    {
        StrCat(str,strSize,insert);
        return 0;
    }
    if (pos == 0)
    {
        Format(str,strSize,"%s%s",insert,str);
        return 0;
    }
    new len = strLen-pos;
    if ((strLen+insLen) >= strSize)
        len = strSize-insLen-pos-1;
    if (len < 0)
    {
        insLen += len;
        len = 0;
    }
    if (insLen <= 0) // This should not be at all possible thanks to the first
        return 1;    //   if statement, but who knows *shrug*
    for (new i = 0;i < len;i++)
        str[i+pos+insLen] = str[i+pos];
    for (new i = 0;i < insLen;i++)
        str[i+pos] = insert[i];
    str[len+pos+insLen] = '\0';
    return 0;
}
// "contains0.." size=11; len=8;
// "five\0" len=4;
// StrInsert(contains,11,five,7) == "containfiv\0";

// "two\0" size=4; len=3;
// "three\0" len=5;
// StrInsert(two,4,three,2) == "twt\0"

// Ignore the above comments, was only there to help with calculations

// Erases len characters from str starting at pos.
// If len is -1 all characters starting at pos are erased.
// Returns the number of characters erased.
// Doesn't actually erase any characters, simply shifts the remaining down
//   and inserts the null terminator.
stock StrErase(String:str[], pos, len = -1)
{
    new strLen = strlen(str);
    if ((len == 0) || (pos > strLen)) // Nothing to erase.
        return 0;
    if ((len < 0) || ((strLen-pos) < len))
    {
        str[pos] = '\0';
        return strLen-pos;
    }
    for (new start = pos+len, end = strLen-start, i = 0;i < end;i++)
        str[pos+i] = str[start+i];
    str[strLen-len] = '\0';
    return len;
}
// StrErase("this is a big string\0",10,4) == "this is a string\0";

// Test if a string is (or begins with) a digit.
// Returns the position in str at the last character in the sequence of
//   leading digits or -1 if str does not begin with a digit.
//  StrIsDigit("42\0") will return 1
//  StrIsDigit("-5foo\0") will return 1
//  StrIsDigit("null5\0") will return -1
//  StrIsDigit("-null5\0") will return -1
//  StrIsDigit("1\0") will return 0
// Undefined behaviour if the string is not null terminated.
stock StrIsDigit(const String:str[])
{
    new strLen = strlen(str);
    if (strLen == 0)
        return -1;
    new pos = 0;
    new bool:neg = false;
    if (str[0] == '-')
    {
        pos++;
        neg = true;
    }
    new num;
    for (;pos < strLen;pos++)
    {
        num = str[pos]-48;
        if ((num < 0) || (num > 9))
        {
            pos--;
            break;
        }
    }
    if ((neg) && ((pos == 0) || (strLen < 2)))
        return -1;
    else
        return pos;
}


