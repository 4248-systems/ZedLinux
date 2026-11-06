say 'Hello from REXX!'

name = 'ZedLinux'
say 'Welcome to' name

total = 0
do i = 1 to 5
	total = total + i
	say 'Adding' i 'gives' total
end

if total = 15 then
	say 'The total is 15.'
else
	say 'The total is not 15.'

call greet 'REXX'
exit 0

greet:
	procedure
	parse arg language
	say 'Have fun exploring' language||'!'
return
