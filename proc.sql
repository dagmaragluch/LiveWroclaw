use livewroclaw2;
drop procedure if exists dodaj_wlasciciela;
delimiter $$

create procedure dodaj_wlasciciela(
	in dlogin varchar(20),
	in dhaslo varchar(50),
	out ret varchar(50)
)
begin
	declare exit handler for 1062 set ret = "login alerady in use";
	insert into wlasciciele values( null, dlogin, sha2( dhaslo, 256 ) );
	set ret = "success";
end$$

delimiter ;

drop procedure if exists dodaj_obiekt;
delimiter $$

create procedure dodaj_obiekt(
	nazwa varchar(50),
	idw int(12),
	adres varchar(50),
	msie smallint(5) unsigned,
	msto smallint(5) unsigned,
	in dlogin varchar(20),
	in dhaslo varchar(50),
	out ret varchar(50)
)
__:begin
	declare _login varchar(20);
	declare _haslo varchar(70);
	declare exit handler for 1452 set ret = "id_wlasciciela not found";
	select login, haslo into _login, _haslo from wlasciciele where id_wlasciciela = idw;
	if _login != dlogin or _haslo != sha2( dhaslo, 256 ) then
		set ret = "authentication failed";
		leave __;
	end if;
	insert into obiekty values( null, idw, nazwa, adres, msie, msto );
	set ret = "success";
end$$

delimiter ;

drop procedure if exists dodaj_koncert;
delimiter $$

create procedure dodaj_koncert(
	id_obiektu int(12),
	id_zespolu int(12),
	data_koncertu date,
	data_sprzedarzy date,
	in dlogin varchar(20),
	in dhaslo varchar(50),
	out ret varchar(50)
)
__:begin
	declare _login varchar(20);
	declare _haslo varchar(70);
	declare exit handler for 1452 set ret = "id_obiektu or id_zespolu not found";
	declare exit handler for 1644 set ret = "incorrect values";
	select login, haslo into _login, _haslo from wlasciciele join obiekty where obiekty.id_wlasciciela = wlasciciele.id_wlasciciela and obiekty.id_obiektu = id_obiektu;
	if _login != dlogin or _haslo != sha2( dhaslo, 256 ) then
		set ret = "authentication failed";
		leave __;
	end if;
	insert into koncerty values( null, id_obiektu, id_zespolu, data_koncertu, data_sprzedarzy, 0, 0, 0, 0 );
	set ret = "success";
end$$

delimiter ;

drop procedure if exists dodaj_bilety;
delimiter $$

create procedure dodaj_bilety(
	num int(12),
	idk int(12),
	cena int(4),
	rodzaj_miejsca enum ('siedzace', 'stojace'),
	in dlogin varchar(20),
	in dhaslo varchar(50),
	out ret varchar(50)
)
__:begin
	declare _login varchar(20) default "";
	declare _haslo varchar(70) default "";
	declare cnt int default 0; -- licznik do pętli
	declare cr int default 0; -- aktualna ilość biletów
	declare mx int default 0; -- maksymalna ilość biletów
	declare fr int default 0; -- pozostale bilety
	declare min_cena int default 0; -- minimalna cena
	declare exit handler for 1452 set ret = "id_koncertu not found";
	declare exit handler for 1048 set ret = "forbidden null value";
	declare exit handler for 1265 set ret = "wrong rodzaj_miejsca value";
	-- autoryzacja
	select login, haslo into _login, _haslo
		from wlasciciele
		join obiekty on obiekty.id_wlasciciela = wlasciciele.id_wlasciciela
		join koncerty on koncerty.id_obiektu = obiekty.id_obiektu
		where koncerty.id_koncertu = idk;
	if _login != dlogin or _haslo != sha2( dhaslo, 256 ) then
		set ret = "authentication failed";
		leave __;
	end if;
	-- pobieramy max i min_cena
	if rodzaj_miejsca = 'siedzace' then
		select obiekty.il_miejsc_siedzacych into mx from obiekty join (select * from koncerty where id_koncertu = idk ) kon on obiekty.id_obiektu = kon.id_obiektu;
	else
		select obiekty.il_miejsc_stojacych into mx from obiekty join (select * from koncerty where id_koncertu = idk ) kon on obiekty.id_obiektu = kon.id_obiektu;
	end if;
	-- liczymy aktualną
	select count( id_biletu ) into cr from bilety where bilety.id_koncertu = idk and bilety.rodzaj_miejsca = rodzaj_miejsca;
	-- if cr+num > mx return error
	if num+cr > mx then
		set ret = "num too big";
		leave __;
	end if;
	start transaction;
	while cnt < num do
		insert into bilety values( null, idk, cena, rodzaj_miejsca, false );
		set cnt = cnt+1;
	end while;
	if rodzaj_miejsca = 'siedzace' then
		update koncerty set il_miejsc_siedzacych = num+cr where id_koncertu = idk;
	else
		update koncerty set il_miejsc_stojacych = num+cr where id_koncertu = idk;
	end if;
	select il_pozostalych_biletow into fr from koncerty where id_koncertu = idk;
	update koncerty set il_pozostalych_biletow = fr + num where id_koncertu = idk;
	select akt_najtanszy_bilet into min_cena from koncerty where id_koncertu = idk;	
	if min_cena > cena or min_cena = 0 then
		update koncerty set akt_najtanszy_bilet = cena where id_koncertu = idk;
	end if;
	commit;
	set ret = "success";
end$$

delimiter ;

drop procedure if exists anuluj_koncert;
delimiter $$

create procedure anuluj_koncert(
	idk int(12),
	in dlogin varchar(20),
	in dhaslo varchar(50),
	out ret varchar(50)
)
__:begin
	declare _login varchar(20);
	declare _haslo varchar(70);
	declare exit handler for 1452 set ret = "id_obiektu not found";
	-- autoryzacja
	select login, haslo into _login, _haslo
		from wlasciciele
		join obiekty on obiekty.id_wlasciciela = wlasciciele.id_wlasciciela
		join koncerty on koncerty.id_obiektu = obiekty.id_obiektu
		where koncerty.id_koncertu = idk;
	if _login != dlogin or _haslo != sha2( dhaslo, 256 ) then
		set ret = "authentication failed";
		leave __;
	end if;
	-- sprawdź czy nie zaczęła się sprzedaż
	if (select data_sprzedarzy from koncerty where id_koncertu = idk ) < now() then
		set ret = "sale already started";
		leave __;
	end if;
	-- usuń bilety
	delete from bilety where id_koncertu = idk;
	-- usuń koncert
	delete from koncerty where id_koncertu = idk;
	set ret = "success";
end$$

delimiter ;

drop trigger if exists koncerty_check;
delimiter $$

create trigger koncerty_check
before insert on koncerty
for each row
begin
	if( new.data_koncertu < now() ) then
		signal sqlstate '45000' set message_text = 'cannot pass past date';
	end if;
	if( new.data_koncertu < new.data_sprzedarzy ) then
		signal sqlstate '45000' set message_text = 'show date earlier than sale date';
	end if;
	if( new.data_koncertu in (select data_koncertu from koncerty where id_obiektu = new.id_obiektu) ) then
		signal sqlstate '45000' set message_text = 'term busy';
	end if;
end$$

delimiter ;

drop procedure if exists autoryzacja;

delimiter $$

create procedure autoryzacja(
	in dlogin varchar(20),
	in dhaslo varchar(50),
	out did int,
	out ret varchar(50)
)
__:begin
	select id_wlasciciela into did from wlasciciele where login = dlogin and haslo = sha2( dhaslo, 256 );
	if did is null then
		set ret = "authentication failed";
		leave __;
	end if;
	set ret = "success";
end$$

delimiter ;

drop procedure if exists aktualizuj_koncerty;

delimiter $$

create procedure aktualizuj_koncerty()
__:begin
	declare done int default 0;
	declare id int default 0;
	
	declare msie int default 0;
	declare msto int default 0;
	declare min_cena int default 0;
	declare pozo int default 0;
	
	declare cur1 cursor for select id_koncertu from koncerty;
	declare continue handler for not found set done = 1;
	
	start transaction;
	
	open cur1;
	while done = 0 do
		fetch cur1 into id;
		select count(*) into msie from bilety where rodzaj_miejsca = 'siedzace' and id_koncertu = id;
		select count(*) into msto from bilety where rodzaj_miejsca = 'stojace' and id_koncertu = id;
		select min(cena), count(*) into min_cena, pozo from bilety where id_koncertu = id and not czy_sprzedany;
		update koncerty set il_miejsc_siedzacych = msie, il_miejsc_stojacych = msto, il_pozostalych_biletow = pozo, akt_najtanszy_bilet = min_cena where id_koncertu = id;
	end while;
	close cur1;
	
	commit;
	
end$$

delimiter ;